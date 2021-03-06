Changelog
=========

v1.0
----
First full release.

v1.0.1
------
Bugfixes, last release before references changes.

Infrastructure
~~~~~~~~~~~~~~

- Transition to CircleCI for testing
- Use production settings by default; see :ref:`note-on-test-settings` for
  more.
- lots o' docs
- new ``include/references_configs`` to help organize references. These are
  currently not used by the workflows directly.
- bugfix: use additional options when uncompressing downloaded reference files
  (``--no-same-owner`` for ``tar``, ``-f`` for ``gunzip``)
- additional dependencies in the top-level environment to support the
  additional features in rnaseq.Rmd and track hubs.
- colocalization workflow, external workflow, figures workflow to demonstrate
  vertical integration

RNA-seq
~~~~~~~
- remove kallisto indexing, use salmon
- improvements to how chipseq sampletables are parsed (with more informative
  error messages)
- run preseq for RNA-seq library complexity QC
- support for merging bigwigs
- featureCounts is now run in all three strandedness modes, and results
  incorporated into MultiQC as separate modules.
- RNA-seq now symlinks "pos" and "neg" bigWigs, which describe how reads map to
  the *reference*, to "sense" and "antisense" bigWigs, which describe the
  *originating RNA*. This makes it easy to swap strands depending on protocol.
- new ``downstream/helpers.Rmd`` which factors out a lot of the work previously
  done in ``rnaseq.Rmd`` into separate functions.
- track hub building respects new sense/antisense bigwig symlinks

``downstream/rnaseq.Rmd``
~~~~~~~~~~~~~~~~~~~~~~~~~
- AnnotationHub uses cache dir that will not clobber default home directory cache
- use varianceStabilizingTransform instead of rlog
- print a size factors table
- use multiple cores for computationally expensive DESeq2 operations
- using separate lists for results, dds objects, and nice labels for automated
  plots for each contrast
- UpSet plots for comparing gene lists across contrasts
- DEGpattern plots for showing clusters of expression patterns (from the
  DEGreport package)
- attach normalized counts per sample and per factor (parsed from the model
  used for the contrast) as well as TPM estimates to the results tables
- trim the labels in GO enrichment plots when too long


ChIP-seq
~~~~~~~~
- sicer for chipseq domain calling
- pin snakemake <4.5.0 so that subworkflows behave correctly
- chipseq peak-calling rules (and therefore wrappers) now expect a chromsizes
  file as input
- bigbed files for narrowPeak and broadPeak files are created correctly
  depending on their format
- run multiBigWigSummary and plotCorrelation from deepTools for ChIP-seq QC
- ChIP-seq track hub generation script

Both RNA-seq and ChIP-seq
~~~~~~~~~~~~~~~~~~~~~~~~~
- update deeptools calls to reflect >v3.0 syntax
- support for SRA run tables so it's trivial to re-run experiments
  in SRA
- multiple FastQC runs are shown separately in MultiQC output

v1.1
----

Infrastructure
~~~~~~~~~~~~~~

- The default settings in Snakefiles are for real-world use, rather than for
  testing. This reduces the amount of editing necessary before running actual
  data. See :ref:`test-settings` for the extra step to take when testing
  locally.

- new ``run_test.sh`` script in each workflow directory to automatically run
  the preprocessor when running test data

- added extensive comments to Snakefiles with ``NOTE:`` string to make it
  obvious where and how to make changes.

- Documentation overhaul to bring everything up to v1.1. This includes Sphinx
  autodocs on the ``lib`` module.

- pytest test suite is run on the ``lib`` module

References
~~~~~~~~~~

- new `metadata` section in references config, which can be used to store
  additional information like mappable bases and genome size.

- References can now be included from other YAML files into the main config
  file. This dramatically simplifies individual configfiles, and allows
  multiple workflows to use identical references without having to do
  error-prone and hard-to-maintain copy/pastes between workflow configs. See
  :ref:`references-config` for details.

- New GTF conversion, ``mappings``. This is intended to replace the
  ``annotation_hub`` conversion, which was problematic because 1) a particular
  annotation hub accession is not guaranteed to be found in new versions of
  AnnotationHub, resulting in lack of reproducibility, and 2) it was difficult
  to synchronize the results with a particular GTF annotation. The
  ``annotation_hub`` conversion is still supported, but if it's used then
  a DeprecationWarning will be emitted, recommending ``mappings`` instead.


Both RNA-seq and ChIP-seq
~~~~~~~~~~~~~~~~~~~~~~~~~

- `fastq_screen` is now configured via ``config.yaml``. This reduces the need
  to edit the Snakefile and coordinate between the config and the fastq_screen
  rule. Now everything is done within the config file.

- `fastq_screen` wrapper now handles additional output files created when using
  the ``--tag`` and ``--filter`` arguments to ``fastq_screen``.

- In the config file, ``assembly`` has been changed to the more-descriptive
  ``organism``. The change is backwards compatible, but a DeprecationWarning is
  raised if ``assembly:`` is still used, and changed to ``organism`` (though
  only in memory, not on disk).

- Patterns no longer use ``{sample_dir}``, ``{agg_dir}``, etc placeholders that
  need to be configured in the config YAML. Instead, these directories are
  hard-coded directly into the patterns. This simplifies the config files,
  simplifies the patterns, and removes one layer of disconnect between the
  filenames and how they are determined.

- removed 4C workflow since it used 4c-ker

ChIP-seq
~~~~~~~~
- macs2 and sicer can accept mappable genome size overrides

RNA-seq
~~~~~~~

- RNA-seq downstream:

    - ``downstream/help_docs.Rmd`` can be included for first-time users to
      describe the sections of the RNA-seq analysis

    - ``rnaseq.Rmd`` now uses the same ``NOTE:`` syntax as the Snakefiles for
      indicating where/what to change

    - Easy swapping of which strand to use from the three featureCounts runs
      performed by the workflow

    - Be explicit about using DESeq2::lfcShrink as is now the default in recent
      DESeq2 versions

    - improved the mechanism for keeping together results objects, dds objects, and
      labels (list of lists, rather than individual list object; refactored
      functions to use this new structure

v1.2
----

- First-class paired-end support, including mixing PE and SE samples in the
  same sampletable
- Support for NextGenMap aligner and STAR aligner
- FASTA files are always symlinked into the directories of indexes that were
  created from it
- Updates to dependencies and MultiQC config


