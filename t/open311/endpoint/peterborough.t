use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use JSON::MaybeXS;
use Test::More;
use Test::MockModule;
use Test::LongString;

sub new_service {
    Open311::Endpoint::Service->new(description => $_[0], service_code => $_[0], service_name => $_[0]);
}

my $confirm = Test::MockModule->new('Open311::Endpoint::Integration::UK::Peterborough::Confirm');
$confirm->mock(services => sub {
    return ( new_service('A_BC'), new_service('D_EF') );
});

my $ezytreev = Test::MockModule->new('Open311::Endpoint::Integration::UK::Peterborough::Ezytreev');
$ezytreev->mock(services => sub {
    return ( new_service('GHI'), new_service('JKL') );
});

my $bartec = Test::MockModule->new('Open311::Endpoint::Integration::UK::Peterborough::Bartec');
$bartec->mock(services => sub {
    return ( new_service('DFOUL'), new_service('RUBB') );
});
$bartec->mock(get_service_requests => sub {
  my $dt = DateTime->new(
      year => 2018,
      month => 04,
      day => 17,
      hour => 13,
      minute => 34,
      second => 56,
      time_zone => 'UTC',
  );

  return (
      new Open311::Endpoint::Service::Request->new(
        service_request_id => 12,
        status => 'open',
        latlong => [ 0, 1 ],
        requested_datetime => $dt,
        updated_datetime => $dt,
        service => Open311::Endpoint::Service->new(
            service_name => 'RUBB',
            service_code => 'RUBB',
        ),
      )
  );
});

use_ok('Open311::Endpoint::Integration::UK::Peterborough');
my $endpoint = Open311::Endpoint::Integration::UK::Peterborough->new;

subtest 'GET service requests' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/requests.xml?jurisdiction_id=peterborough&start_date=2018-04-17T00:00:00Z&end_date=2018-04-18T00:00:00Z'
    );
    ok $res->is_success, 'xml success'
        or diag $res->content;
    is_string $res->content, <<CONTENT, 'xml string ok';
<?xml version="1.0" encoding="utf-8"?>
<service_requests>
  <request>
    <address></address>
    <address_id></address_id>
    <lat>0</lat>
    <long>1</long>
    <media_url></media_url>
    <requested_datetime>2018-04-17T13:34:56Z</requested_datetime>
    <service_code>Bartec-RUBB</service_code>
    <service_name>RUBB</service_name>
    <service_request_id>Bartec-12</service_request_id>
    <status>open</status>
    <updated_datetime>2018-04-17T13:34:56Z</updated_datetime>
    <zipcode></zipcode>
  </request>
</service_requests>
CONTENT

};

done_testing();
