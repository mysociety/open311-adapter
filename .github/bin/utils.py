import hashlib
import os
import subprocess


def get_bundle_filename():
    root = os.path.join(os.path.dirname(__file__), '..', '..')
    with open(os.path.join(root, 'cpanfile.snapshot')) as cpanfile:
        hash = hashlib.md5(cpanfile.read()).hexdigest()

    try:
        version = os.environ['TRAVIS_PERL_VERSION']
    except KeyError:
        # Not running on CI, get from running perl
        version = subprocess.check_output("perl -e 'print $^V =~ /^v(5\.\d+)/;'")

    version = '-%s' % version

    if 'GITHUB_WORKFLOW' in os.environ:
        suffix = '-github-'
    else:
        suffix = '-'

    filename = 'open311-adapter-local%s%s%s.tgz' % (suffix, hash, version)
    return filename
