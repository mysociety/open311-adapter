use strict;
use warnings;
use Test::More;
use File::Basename;

BEGIN { $ENV{TEST_MODE} = 1; }

test_multi(0, 'Open311::Endpoint::Integration::UK',
    'Open311::Endpoint::Integration::UK::BANES' => 'banes_confirm',
    'Open311::Endpoint::Integration::UK::CheshireEast' => 'cheshireeast_confirm',
    'Open311::Endpoint::Integration::UK::EastSussex' => 'eastsussex_salesforce',
    'Open311::Endpoint::Integration::UK::Gloucestershire' => 'gloucestershire_confirm',
    'Open311::Endpoint::Integration::UK::Hounslow' => 'hounslow_confirm',
    'Open311::Endpoint::Integration::UK::IslandRoads' => 'island_roads_confirm',
    'Open311::Endpoint::Integration::UK::Kingston' => 'kingston_echo',
    'Open311::Endpoint::Integration::UK::Lincolnshire' => 'lincolnshire_confirm',
    'Open311::Endpoint::Integration::UK::NorthumberlandAlloy' => 'northumberland_alloy',
    'Open311::Endpoint::Integration::UK::Rutland' => 'rutland',
    'Open311::Endpoint::Integration::UK::Shropshire' => 'shropshire_confirm',
    'Open311::Endpoint::Integration::UK::Southwark' => 'southwark_confirm',
    'Open311::Endpoint::Integration::UK::Surrey' => 'surrey_boomi',
    'Open311::Endpoint::Integration::UK::Sutton' => 'sutton_echo',
    'Open311::Endpoint::Integration::UK::Hampshire' => 'hampshire_confirm',
);

test_multi(1, 'Open311::Endpoint::Integration::UK::Bexley',
    'Open311::Endpoint::Integration::UK::Bexley::Symology' => 'bexley_symology',
    'Open311::Endpoint::Integration::UK::Bexley::ConfirmGrounds' => 'bexley_confirm_grounds',
    'Open311::Endpoint::Integration::UK::Bexley::ConfirmTrees' => 'bexley_confirm_trees',
    'Open311::Endpoint::Integration::UK::Bexley::Uniform' => 'bexley_uniform',
    'Open311::Endpoint::Integration::UK::Bexley::Whitespace' => 'bexley_whitespace',
    'Open311::Endpoint::Integration::UK::Bexley::Agile' => 'bexley_agile',
);

test_multi(1, 'Open311::Endpoint::Integration::UK::Brent',
    'Open311::Endpoint::Integration::UK::Brent::Symology' => 'brent_symology',
    'Open311::Endpoint::Integration::UK::Brent::Echo' => 'brent_echo',
    'Open311::Endpoint::Integration::UK::Brent::ATAK' => 'brent_atak',
);

test_multi(0, 'Open311::Endpoint::Integration::UK::Bromley',
    'Open311::Endpoint::Integration::UK::Bromley::Echo' => 'bromley_echo',
    #'Open311::Endpoint::Integration::UK::Bromley::Passthrough' => 'www.bromley.gov.uk',
);

test_multi(0, 'Open311::Endpoint::Integration::UK::Merton',
    'Open311::Endpoint::Integration::UK::Merton::Echo' => 'merton_echo',
    #'Open311::Endpoint::Integration::UK::Merton::Passthrough' => 'www.merton.gov.uk',
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

test_multi(1, 'Open311::Endpoint::Integration::UK::Buckinghamshire',
    'Open311::Endpoint::Integration::UK::Buckinghamshire::Alloy' => 'buckinghamshire_alloy',
    'Open311::Endpoint::Integration::UK::Buckinghamshire::Abavus' => 'buckinghamshire_abavus',
);

test_multi(1, 'Open311::Endpoint::Integration::UK::CentralBedfordshire',
    'Open311::Endpoint::Integration::UK::CentralBedfordshire::Symology' => 'centralbedfordshire_symology',
    'Open311::Endpoint::Integration::UK::CentralBedfordshire::Jadu' => 'centralbedfordshire_jadu',
);

test_multi(1, 'Open311::Endpoint::Integration::UK::Camden',
    'Open311::Endpoint::Integration::UK::Camden::Symology' => 'camden_symology',
    'Open311::Endpoint::Integration::UK::Camden::ConfirmTrees' => 'camden_confirm_trees',
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
