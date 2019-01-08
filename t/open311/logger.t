package LoggerTest;

use Moo;
use Path::Tiny;
extends 'Open311::Endpoint::Logger';

has min_log_level => (
    is => 'ro',
    default => '',
);

has log_dump_calls => (
    is => 'ro',
    default => '',
);

sub _build_config {
    my $self = shift;
    {
        logfile => path(__FILE__)->sibling("test.log")->stringify,
        min_log_level => $self->min_log_level,
        log_dump_calls => $self->log_dump_calls,
    }
}

package main;

use strict; use warnings;
use Test::More;
use Test::MockTime ':all';

use Path::Tiny;

use Open311::Endpoint::Logger;

my $l = LoggerTest->new();
ok $l, 'can create logger';

my $log_file = $l->config->{logfile};

# truncate log file from previous tests
path($log_file)->spew(());

my @log = path($log_file)->lines;

is scalar(@log), 0, 'Log file contains no entries';

set_fixed_time('2019-01-01T12:32:18Z');
for my $test (
    {
        desc => 'basic log writing',
        config => {},
        level => 'error',
        msg => 'This is an error',
        linecount => 1,
        linenum => 0,
        linematch => '^[2019-01-01T12:32:18] error This is an error',
    },
    {
        desc => 'writing below min level ignored',
        config => {},
        level => 'debug',
        msg => 'This is some debug',
        linecount => 1,
    },
    {
        desc => 'can change minimum level',
        config => { min_log_level => 'debug' },
        level => 'debug',
        msg => 'This is some debug',
        linecount => 2,
        linenum => 1,
        linematch => 'This is some debug',
    },
    {
        desc => 'dump calls ignored by default',
        config => { min_log_level => 'debug' },
        level => 'dump',
        msg => { test => 'result' },
        linecount => 2,
    },
    {
        desc => 'dump calls can be enabled',
        config => { min_log_level => 'debug', log_dump_calls => 1 },
        level => 'dump',
        msg => { test => 'result' },
        linecount => 6,
        linenum => 2,
        linematch => 'VAR1',
    },
) {
    subtest $test->{desc} => sub {
        my $l = LoggerTest->new( $test->{config} );
        my $level = $test->{level};
        $l->$level($test->{msg});

        my @log = path($log_file)->lines;
        is scalar @log, $test->{linecount}, "Correct line count for logfile";

        if ( $test->{linenum} ) {
            ok $log[$test->{linenum}] =~ /$test->{linematch}/, 'Correct line written to logfile';
        }
    };
}
restore_time();
done_testing();
