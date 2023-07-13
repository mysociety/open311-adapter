use strict;
use warnings;

use Test::MockModule;
use Test::More;

use Geocode::SinglePoint;
use LWP::UserAgent;
use Moo;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

subtest "get_nearest_addresses" => sub {
    my $ua = Test::MockModule->new('LWP::UserAgent');
    $ua->mock('get', sub {
        my $resp = HTTP::Response->new(200);
        $resp->content(path(__FILE__)->sibling("files/singlepoint/spatial_radial_search_by_easting_and_northing_response.xml")->slurp);
        return $resp;
    });
    my $singlepoint = Geocode::SinglePoint->new();
    # Call with arbitrary easting, northing and radius.
    my $addresses = $singlepoint->get_nearest_addresses(0, 0, 0, ["STREET", "USRN", "TOWN"]);

    is_deeply $addresses, [
          {
            'TOWN' => 'Chicksands',
            'STREET' => 'Monks Walk',
            'USRN' => '25202550'
          },
          {
            'TOWN' => 'Haynes',
            'STREET' => 'Northwood End Road',
            'USRN' => '25201736'
          },
    ];
};

done_testing;
