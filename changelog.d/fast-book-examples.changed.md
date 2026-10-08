The optional local book-example tool groups each page's examples, checks
pages in parallel, and reuses the compiled-package cache. Hosted checks now
build and lint the book and compare repository signatures without evaluating
examples. The default local gate also uses this offline signature mode;
`--full` opts into runtime examples and displayed-value comparisons.
