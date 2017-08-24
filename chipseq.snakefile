import os
from textwrap import dedent
import yaml
import tempfile
import pandas as pd
from lcdblib.snakemake import helpers, aligners
from lcdblib.utils import utils
from lib import common, chipseq



include: 'references.snakefile'

shell.prefix('set -euo pipefail; export TMPDIR={};'.format(common.tempdir_for_biowulf()))
shell.executable('/bin/bash')
common.get_references_dir(config)

samples, sampletable = common.get_sampletable(config)
refdict, conversion_kwargs = common.references_dict(config)

assembly = config['assembly']

sample_dir = config.get('sample_dir', 'samples')
agg_dir = config.get('aggregation_dir', 'aggregation')
peak_calling = config.get('peaks_dir', 'chipseq')

# ----------------------------------------------------------------------------
# PATTERNS
# ----------------------------------------------------------------------------
patterns = {
    'fastq':   '{sample_dir}/{sample}/{sample}_R1.fastq.gz',
    'cutadapt': '{sample_dir}/{sample}/{sample}_R1.cutadapt.fastq.gz',
    'bam':     '{sample_dir}/{sample}/{sample}.cutadapt.bam',
    'fastqc': {
        'raw': '{sample_dir}/{sample}/fastqc/{sample}_R1.fastq.gz_fastqc.zip',
        'cutadapt': '{sample_dir}/{sample}/fastqc/{sample}_R1.cutadapt.fastq.gz_fastqc.zip',
        'bam': '{sample_dir}/{sample}/fastqc/{sample}.cutadapt.bam_fastqc.zip',
    },
    'libsizes': {
        'fastq':   '{sample_dir}/{sample}/{sample}_R1.fastq.gz.libsize',
        'cutadapt': '{sample_dir}/{sample}/{sample}_R1.cutadapt.fastq.gz.libsize',
        'bam':     '{sample_dir}/{sample}/{sample}.cutadapt.bam.libsize',
    },
    'fastq_screen': '{sample_dir}/{sample}/{sample}.cutadapt.screen.txt',
    'libsizes_table': '{agg_dir}/libsizes_table.tsv',
    'libsizes_yaml': '{agg_dir}/libsizes_table_mqc.yaml',
    'multiqc': '{agg_dir}/multiqc.html',
    'markduplicates': {
        'bam': '{sample_dir}/{sample}/{sample}.cutadapt.markdups.bam',
        'metrics': '{sample_dir}/{sample}/{sample}.cutadapt.markdups.bam.metrics',
    },
    'bigwig': '{sample_dir}/{sample}/{sample}.cutadapt.bam.bigwig',
    'peaks': {
        'macs2': '{peak_calling}/macs2/{macs2_run}/peaks.bed',
        'spp': '{peak_calling}/spp/{spp_run}/peaks.bed',
    },
    'bigbed': {
        'macs2': '{peak_calling}/macs2/{macs2_run}/peaks.bigbed',
        'spp': '{peak_calling}/spp/{spp_run}/peaks.bigbed',
    },

}
fill = dict(sample=samples, sample_dir=sample_dir, agg_dir=agg_dir,
            peak_calling=peak_calling,
            macs2_run=chipseq.peak_calling_dict(dict(config), algorithm='macs2'),
            spp_run=chipseq.peak_calling_dict(dict(config), algorithm='spp'),
           )
targets = helpers.fill_patterns(patterns, fill)


def wrapper_for(path):
    return 'file:' + os.path.join('wrappers', 'wrappers', path)

# ----------------------------------------------------------------------------
# RULES
# ----------------------------------------------------------------------------

rule targets:
    """
    Final targets to create
    """
    input:
        (
            targets['bam'] +
            utils.flatten(targets['fastqc']) +
            utils.flatten(targets['libsizes']) +
            [targets['fastq_screen']] +
            [targets['libsizes_table']] +
            [targets['multiqc']] +
            utils.flatten(targets['markduplicates']) +
            utils.flatten(targets['bigwig']) +
            utils.flatten(targets['peaks'])
        )


rule cutadapt:
    """
    Run cutadapt
    """
    input:
        fastq=patterns['fastq']
    output:
        fastq=patterns['cutadapt']
    log:
        patterns['cutadapt'] + '.log'
    params:
        extra='-a file:include/adapters.fa -q 20 --minimum-length=25'
    wrapper:
        wrapper_for('cutadapt')


rule fastqc:
    """
    Run FastQC
    """
    input: '{sample_dir}/{sample}/{sample}{suffix}'
    output:
        html='{sample_dir}/{sample}/fastqc/{sample}{suffix}_fastqc.html',
        zip='{sample_dir}/{sample}/fastqc/{sample}{suffix}_fastqc.zip',
    wrapper:
        wrapper_for('fastqc')


rule bowtie2:
    """
    Map reads with Bowtie2
    """
    input:
        fastq=rules.cutadapt.output.fastq,
        index=[refdict[assembly][config['aligner']['tag']]['bowtie2']]
    output:
        bam=patterns['bam']
    log:
        patterns['bam'] + '.log'
    params:
        samtools_view_extra='-F 0x04'
    threads: 6
    wrapper:
        wrapper_for('bowtie2/align')


rule fastq_count:
    """
    Count reads in a FASTQ file
    """
    input:
        fastq='{sample_dir}/{sample}/{sample}{suffix}.fastq.gz'
    output:
        count='{sample_dir}/{sample}/{sample}{suffix}.fastq.gz.libsize'
    shell:
        'zcat {input} | echo $((`wc -l`/4)) > {output}'


rule bam_count:
    """
    Count reads in a BAM file
    """
    input:
        bam='{sample_dir}/{sample}/{sample}{suffix}.bam'
    output:
        count='{sample_dir}/{sample}/{sample}{suffix}.bam.libsize'
    shell:
        'samtools view -c {input} > {output}'


rule bam_index:
    """
    Index a BAM
    """
    input:
        bam='{prefix}.bam'
    output:
        bai='{prefix}.bam.bai'
    wrapper: wrapper_for('samtools/index')


rule fastq_screen:
    """
    Run fastq_screen to look for contamination from other genomes
    """
    input:
        fastq=rules.cutadapt.output.fastq,
        dm6=refdict[assembly][config['aligner']['tag']]['bowtie2'],
        phix=refdict['phix']['default']['bowtie2']
    output:
        txt=patterns['fastq_screen']
    log:
        patterns['fastq_screen'] + '.log'
    params: subset=100000
    wrapper:
        wrapper_for('fastq_screen')


rule libsizes_table:
    """
    Aggregate fastq and bam counts in to a single table
    """
    input:
        utils.flatten(targets['libsizes'])
    output:
        json=patterns['libsizes_yaml'],
        tsv=patterns['libsizes_table']
    run:
        def sample(f):
            return os.path.basename(os.path.dirname(f))

        def million(f):
            return float(open(f).read()) / 1e6

        def stage(f):
            return os.path.basename(f).split('.', 1)[1].replace('.gz', '').replace('.count', '')

        df = pd.DataFrame(dict(filename=list(map(str, input))))
        df['sample'] = df.filename.apply(sample)
        df['million'] = df.filename.apply(million)
        df['stage'] = df.filename.apply(stage)
        df = df.set_index('filename')
        df = df.pivot('sample', columns='stage', values='million')
        df.to_csv(output.tsv, sep='\t')
        y = {
            'id': 'libsizes_table',
            'section_name': 'Library sizes',
            'description': 'Library sizes at various stages of the pipeline',
            'plot_type': 'table',
            'pconfig': {
                'id': 'libsizes_table_table',
                'title': 'Library size table',
                'min': 0
            },
            'data': yaml.load(df.transpose().to_json()),
        }
        with open(output.json, 'w') as fout:
            yaml.dump(y, fout, default_flow_style=False)


rule multiqc:
    """
    Aggregate various QC stats and logs into a single HTML report with MultiQC
    """
    input:
        files=(
            utils.flatten(targets['fastqc']) +
            utils.flatten(targets['libsizes_yaml']) +
            utils.flatten(targets['cutadapt']) +
            utils.flatten(targets['bam']) +
            utils.flatten(targets['markduplicates']) +
            utils.flatten(targets['fastq_screen'])
        ),
        config='config/multiqc_config.yaml'
    output: list(set(targets['multiqc']))
    params:
        analysis_directory=" ".join([sample_dir, agg_dir]),
        extra='--config config/multiqc_config.yaml',
    log: list(set(targets['multiqc']))[0] + '.log'
    wrapper:
        wrapper_for('multiqc')


rule markduplicates:
    """
    Mark or remove PCR duplicates with Picard MarkDuplicates
    """
    input:
        bam=rules.bowtie2.output
    output:
        bam=patterns['markduplicates']['bam'],
        metrics=patterns['markduplicates']['metrics']
    log:
        patterns['markduplicates']['bam'] + '.log'
    wrapper:
        wrapper_for('picard/markduplicates')


rule bigwig:
    """
    Create a bigwig for negative-strand reads
    """
    input:
        bam=patterns['bam'],
        bai=patterns['bam'] + '.bai',
    output: patterns['bigwig']

    # NOTE: for testing, we remove --normalizeUsingRPKM since it results in
    # a ZeroDivisionError (there are less than 1000 reads total). However it is
    # probably a good idea to use that argument with real-world data.
    params:
        extra = '--minMappingQuality 20 --ignoreDuplicates --smoothLength 10'
    log:
        patterns['bigwig'] + '.log'

    wrapper: wrapper_for('deeptools/bamCoverage')


rule bed_to_bigbed:
    input: "data/chipseq/peakcalling/{algorithm}/{label}/{prefix}.bed"
    output: "data/chipseq/peakcalling/{algorithm}/{label}/{prefix}.bigbed"
    log: "data/chipseq/peakcalling/{algorithm}/{label}/{prefix}.bigbed.log"
    run:
        p = {
            'macs2': ('assets/narrowPeak.as', '4+6', _narrowpeak),
            'macs2_lenient': ('assets/narrowPeak.as', '4+6', _narrowpeak),
            'macs2_broad': ('assets/broadPeak.as', '4+6', _broadpeak),
            'spp': ('assets/narrowPeak.as', '6+4', _narrowpeak),
        }
        _as, bedplus, conversion = p[wildcards.algorithm]

        if conversion is not None:
            conversion(input[0], input[0] + '.tmp')
        else:
            shell('cp {input} {input}.tmp')

        if len(pybedtools.BedTool(input[0])) == 0:
            shell("touch {output}")
        else:
            shell(
                """sort -k1,1 -k2,2n {input}.tmp | awk -F "\\t" '{{OFS="\\t"; if (($2>0) && ($3>0)) print $0}}' > {input}.tmp.sorted """
                "&& bedToBigBed "
                "-type=bed{bedplus} "
                "-as={_as} "
                "{input}.tmp.sorted "
                "dm6.chromsizes "
                "{output} &> {log} "
                "&& rm {input}.tmp && rm {input}.tmp.sorted")


rule macs2:
    """
    Run the macs2 peak caller
    """
    input:
        ip=lambda wc:
            expand(
                patterns['bam'],
                sample=chipseq.samples_for_run(config, wc.macs2_run, 'macs2', 'ip'),
                sample_dir=sample_dir
            ),
        control=lambda wc:
            expand(
                patterns['bam'],
                sample=chipseq.samples_for_run(config, wc.macs2_run, 'macs2', 'control'),
                sample_dir=sample_dir
            ),
    output: bed=patterns['peaks']['macs2']
    log: patterns['peaks']['macs2'] + '.log'
    params: block=lambda wc: chipseq.block_for_run(config, wc.macs2_run, 'macs2')
    wrapper: wrapper_for('macs2/callpeak')


rule spp:
    """
    Run the SPP peak caller
    """
    input:
        ip=lambda wc:
            expand(
                patterns['bam'],
                sample=chipseq.samples_for_run(config, wc.spp_run, 'spp', 'ip'),
                sample_dir=sample_dir
            ),
        control=lambda wc:
            expand(
                patterns['bam'],
                sample=chipseq.samples_for_run(config, wc.spp_run, 'spp', 'control'),
                sample_dir=sample_dir
            ),
    output:
        bed=patterns['peaks']['spp'],
        enrichment_estimates=patterns['peaks']['spp'] + '.est.wig',
        smoothed_enrichment_mle=patterns['peaks']['spp'] + '.mle.wig',
        rdata=patterns['peaks']['spp'] + '.RData'
    log: patterns['peaks']['spp'] + '.log'
    params: block=lambda wc: chipseq.block_for_run(config, wc.spp_run, 'spp')
    wrapper: wrapper_for('spp')

# vim: ft=python
