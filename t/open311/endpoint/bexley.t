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

my $confirm_grounds = Test::MockModule->new('Open311::Endpoint::Integration::UK::Bexley::ConfirmGrounds');
$confirm_grounds->mock(services => sub {
    return ( new_service('A_BC'), new_service('D_EF') );
});
my $confirm_trees = Test::MockModule->new('Open311::Endpoint::Integration::UK::Bexley::ConfirmTrees');
$confirm_trees->mock(services => sub {
    return ( new_service('X_YZ'), new_service('D_EF') );
});
$confirm_trees->mock(post_service_request_update => sub {
    my ($self, $args) = @_;
    is $args->{service_code}, 'D_EF';
    is $args->{service_request_id}, 1001;
    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => 'in_progress',
        update_id => 456,
    );
});
my $symology = Test::MockModule->new('Open311::Endpoint::Integration::UK::Bexley::Symology');
$symology->mock(services => sub {
    return ( new_service('GHI'), new_service('JKL') );
});
$symology->mock(post_service_request => sub {
    my ($self, $service, $args) = @_;
    is $args->{service_code}, 'GHI';
    is $service->service_code, 'GHI';
    return Open311::Endpoint::Service::Request->new(
        service_request_id => 1001,
    );
});

use_ok('Open311::Endpoint::Integration::UK::Bexley');

my $endpoint = Open311::Endpoint::Integration::UK::Bexley->new;

subtest "GET Service List" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success'
        or diag $res->content;
    is_string $res->content, <<CONTENT, 'xml string ok';
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>A_BC</description>
    <group></group>
    <keywords></keywords>
    <metadata>false</metadata>
    <service_code>ConfirmGrounds-A_BC</service_code>
    <service_name>A_BC</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>D_EF</description>
    <group></group>
    <keywords></keywords>
    <metadata>false</metadata>
    <service_code>ConfirmGrounds-D_EF</service_code>
    <service_name>D_EF</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>X_YZ</description>
    <group></group>
    <keywords></keywords>
    <metadata>false</metadata>
    <service_code>ConfirmTrees-X_YZ</service_code>
    <service_name>X_YZ</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>D_EF</description>
    <group></group>
    <keywords></keywords>
    <metadata>false</metadata>
    <service_code>ConfirmTrees-D_EF</service_code>
    <service_name>D_EF</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>GHI</description>
    <group></group>
    <keywords></keywords>
    <metadata>false</metadata>
    <service_code>GHI</service_code>
    <service_name>GHI</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>JKL</description>
    <group></group>
    <keywords></keywords>
    <metadata>false</metadata>
    <service_code>JKL</service_code>
    <service_name>JKL</service_name>
    <type>realtime</type>
  </service>
</services>
CONTENT
};

subtest "GET Service Definition" => sub {
    my $res = $endpoint->run_test_request( GET => '/services/ConfirmGrounds-A_BC.xml' );
    ok $res->is_success, 'xml success',
        or diag $res->content;
    is_string $res->content, <<CONTENT, 'xml string ok';
<?xml version="1.0" encoding="utf-8"?>
<service_definition>
  <attributes>
  </attributes>
  <service_code>ConfirmGrounds-A_BC</service_code>
</service_definition>
CONTENT

    $res = $endpoint->run_test_request( GET => '/services/JKL.json' );
    ok $res->is_success, 'json success';
    is_deeply decode_json($res->content),
        {
            "service_code" => "JKL",
            "attributes" => [
            ],
        }, 'json structure ok';
};

subtest "POST service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'GHI',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "1001"
        } ], 'correct json returned';
};

subtest "POST update OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2019-03-01T12:00:00Z',
        service_code => 'ConfirmTrees-D_EF',
        service_request_id => "ConfirmTrees-1001",
        status => 'IN_PROGRESS',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the update",
        service_request_id_ext => 5678,
        update_id => 456,
        media_url => 'http://example.org/photo/1.jpeg',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            'update_id' => "ConfirmTrees-456",
        } ], 'correct json returned';
};

done_testing;
