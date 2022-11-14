use strict;
use warnings;
use Test::More;
use File::Basename;

BEGIN { $ENV{TEST_MODE} = 1; }

test_multi(0, 'Open311::Endpoint::Integration::UK',
    'Open311::Endpoint::Integration::UK::BANES' => 'banes_confirm',
    'Open311::Endpoint::Integration::UK::Bromley' => 'bromley_echo',
    'Open311::Endpoint::Integration::UK::Buckinghamshire' => 'buckinghamshire_confirm',
    'Open311::Endpoint::Integration::UK::Camden' => 'camden_symology',
    'Open311::Endpoint::Integration::UK::CentralBedfordshire' => 'centralbedfordshire_symology',
    'Open311::Endpoint::Integration::UK::CheshireEast' => 'cheshireeast_confirm',
    'Open311::Endpoint::Integration::UK::EastSussex' => 'eastsussex_salesforce',
    'Open311::Endpoint::Integration::UK::Hounslow' => 'hounslow_confirm',
    'Open311::Endpoint::Integration::UK::IslandRoads' => 'island_roads_confirm',
    'Open311::Endpoint::Integration::UK::Kingston' => 'kingston_echo',
    'Open311::Endpoint::Integration::UK::Lincolnshire' => 'lincolnshire_confirm',
    'Open311::Endpoint::Integration::UK::Rutland' => 'rutland',
    'Open311::Endpoint::Integration::UK::Shropshire' => 'shropshire_confirm',
    'Open311::Endpoint::Integration::UK::Sutton' => 'sutton_echo',
    'Open311::Endpoint::Integration::UK::Hampshire' => 'hampshire_confirm',
);

test_multi(1, 'Open311::Endpoint::Integration::UK::Bexley',
    'Open311::Endpoint::Integration::UK::Bexley::Symology' => 'bexley_symology',
    'Open311::Endpoint::Integration::UK::Bexley::ConfirmGrounds' => 'bexley_confirm_grounds',
    'Open311::Endpoint::Integration::UK::Bexley::ConfirmTrees' => 'bexley_confirm_trees',
    'Open311::Endpoint::Integration::UK::Bexley::Uniform' => 'bexley_uniform',
);

test_multi(1, 'Open311::Endpoint::Integration::UK::Brent',
    'Open311::Endpoint::Integration::UK::Brent::Symology' => 'brent_symology',
    'Open311::Endpoint::Integration::UK::Brent::Echo' => 'brent_echo',
);

test_multi(1, 'Open311::Endpoint::Integration::UK::Peterborough',
    'Open311::Endpoint::Integration::UK::Peterborough::Confirm' => 'peterborough_confirm',
    'Open311::Endpoint::Integration::UK::Peterborough::Ezytreev' => 'peterborough_ezytreev',
    'Open311::Endpoint::Integration::UK::Peterborough::Bartec' => 'peterborough_bartec',
);

test_multi(1, 'Open311::Endpoint::Integration::UK::Oxfordshire',
    'Open311::Endpoint::Integration::UK::Oxfordshire::WDM' => 'oxfordshire_wdm',
    'Open311::Endpoint::Integration::UK::Oxfordshire::AlloyV2' => 'oxfordshire_alloy_v2',
);

test_multi(1, 'Open311::Endpoint::Integration::UK::Hackney',
    'Open311::Endpoint::Integration::UK::Hackney::Highways' => 'hackney_highways_alloy_v2',
    'Open311::Endpoint::Integration::UK::Hackney::Environment' => 'hackney_environment_alloy_v2',
);

done_testing;

sub test_multi {
    my ($must_have, $endpoint, %config_filenames) = @_;

    use_ok($endpoint);
    $endpoint = $endpoint->new;

    foreach ($endpoint->plugins) {
        next unless $must_have || $_->can('get_integration');
        my $integ = $_->get_integration;
        next unless $must_have || $integ->can('config_filename');
        my $name = delete $config_filenames{ref($_)};
        is $integ->config_filename, $name;
        is basename($integ->config_file), "council-$name.yml";
    }

    is_deeply \%config_filenames, {};
}
