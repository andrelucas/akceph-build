# README for Debian package smoke tests

<!-- vscode-markdown-toc -->
* [Invocation](#Invocation)
* [Tests](#Tests)

<!-- vscode-markdown-toc-config
	numbering=false
	autoSave=true
	/vscode-markdown-toc-config -->
<!-- /vscode-markdown-toc -->

Run some Debian package smoke tests.

## <a name='Invocation'></a>Invocation

Run with:

```sh
# RELEASEDIR is the release directory to test. It will typically begin with
# `release_`. It will typically be a relative directory; where necessary
# the test scripts will convert to a full path.

./run_tests RELEASEDIR
```

## <a name='Tests'></a>Tests

The `test/` directory will be scanned for filenames starting with `test_`.
Each matching file will be run by `run_tests.sh`, with the following
environment variables set:

| Variable | Purpose |
| - | - |
| RELEASEDIR | The directory containing the Debian build output. May be a relative directory -  |

If and only if all tests run and pass, `run_tests.sh` will exit with zero
status.
