use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;

use_ok 'Open311::Endpoint::Integration::UK::Bromley';

done_testing;
