use strict;
use warnings;
use Test::More;
use File::Basename;

BEGIN { $ENV{TEST_MODE} = 1; }

use_ok('Open311::Endpoint::Integration::UK');

my $endpoint = Open311::Endpoint::Integration::UK->new;

my %config_filenames = (
    'Open311::Endpoint::Integration::UK::BANES' => 'banes_confirm',
    'Open311::Endpoint::Integration::UK::Bromley' => 'bromley_echo',
    'Open311::Endpoint::Integration::UK::Buckinghamshire' => 'buckinghamshire_confirm',
    'Open311::Endpoint::Integration::UK::CheshireEast' => 'cheshireeast_confirm',
    'Open311::Endpoint::Integration::UK::EastSussex' => 'eastsussex_salesforce',
    'Open311::Endpoint::Integration::UK::Hounslow' => 'hounslow_confirm',
    'Open311::Endpoint::Integration::UK::Hackney' => 'hackney_highways_alloy_v2',
    'Open311::Endpoint::Integration::UK::IslandRoads' => 'island_roads_confirm',
    'Open311::Endpoint::Integration::UK::Lincolnshire' => 'lincolnshire_confirm',
    'Open311::Endpoint::Integration::UK::Northamptonshire' => 'northamptonshire_alloy',
    'Open311::Endpoint::Integration::UK::Oxfordshire' => 'oxfordshire',
    'Open311::Endpoint::Integration::UK::Rutland' => 'rutland',
    'Open311::Endpoint::Integration::UK::NorthamptonshireAlloyV2' => 'northamptonshire_alloy_v2',
);

foreach ($endpoint->plugins) {
    next unless $_->can('get_integration');
    my $integ = $_->get_integration;
    next unless $integ->can('config_filename');
    my $name = delete $config_filenames{ref($_)};
    is $integ->config_filename, $name;
    is basename($integ->config_file), "council-$name.yml";
}

is_deeply \%config_filenames, {};

use_ok('Open311::Endpoint::Integration::UK::Bexley');

$endpoint = Open311::Endpoint::Integration::UK::Bexley->new;

%config_filenames = (
    'Open311::Endpoint::Integration::UK::Bexley::Symology' => 'bexley_symology',
    'Open311::Endpoint::Integration::UK::Bexley::ConfirmGrounds' => 'bexley_confirm_grounds',
    'Open311::Endpoint::Integration::UK::Bexley::ConfirmTrees' => 'bexley_confirm_trees',
    'Open311::Endpoint::Integration::UK::Bexley::Uniform' => 'bexley_uniform',
);

foreach ($endpoint->plugins) {
    my $integ = $_->get_integration;
    my $name = delete $config_filenames{ref($_)};
    is $integ->config_filename, $name;
    is basename($integ->config_file), "council-$name.yml";
}

is_deeply \%config_filenames, {};

use_ok('Open311::Endpoint::Integration::UK::Peterborough');

$endpoint = Open311::Endpoint::Integration::UK::Peterborough->new;

%config_filenames = (
    'Open311::Endpoint::Integration::UK::Peterborough::Confirm' => 'peterborough_confirm',
    'Open311::Endpoint::Integration::UK::Peterborough::Ezytreev' => 'peterborough_ezytreev',
    'Open311::Endpoint::Integration::UK::Peterborough::Bartec' => 'peterborough_bartec',
);

foreach ($endpoint->plugins) {
    my $integ = $_->get_integration;
    my $name = delete $config_filenames{ref($_)};
    is $integ->config_filename, $name;
    is basename($integ->config_file), "council-$name.yml";
}

is_deeply \%config_filenames, {};

done_testing;
