package Mock::Response;

use Moo;
use Encode;
use Types::Standard ':all';
use utf8;

has content => (
    is => 'ro',
    isa => Str,
    default => '[]',
    coerce => sub { encode_utf8($_[0]) }
);

has code => (
    is => 'ro',
    isa => Str,
    default => '200',
);

has message => (
    is => 'ro',
    isa => Str,
    default => 'OK',
);

has is_success => (
    is => 'ro',
    isa => Bool,
    default => 1
);

package Integrations::Alloy::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Alloy';
with 'Role::Config';
has config_filename => ( is => 'ro', default => 'dummy' );
sub _build_config_file { path(__FILE__)->sibling("alloy.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Alloy';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("alloy.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Alloy::Dummy');
sub service_request_content { '/open311/service_request_extended' }

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::MockTime ':all';
use Encode;

use Open311::Endpoint;
use Data::Dumper;
use JSON::MaybeXS;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

my %responses = (
    resource => '{
    }',
);

my @sent;
my @calls;

my $integration = Test::MockModule->new('Integrations::Alloy');
$integration->mock('api_call', sub {
    my ($self, %args) = @_;
    my $call = $args{call};
    my $params = $args{params};
    my $body = $args{body};

    my $content = '[]';
    push @calls, $call;
    if ( $body ) {
        push @sent, $body;
        if ( $call eq 'resource' ) {
            $content = '{ "resourceId": 12345 }';
        } elsif ( $call eq 'resource/12345' ) {
            $content = '{ "systemVersionId": 8011 }';
        } elsif ( $call =~ 'search/resource-fetch' ) {
            my $type = $body->{aqsNode}->{properties}->{entityCode};
            my $time = $body->{aqsNode}->{children}->[0]->{children}->[1]->{properties}->{value}->[0];
            if ( $type =~ /DEFECT/ ) {
                if ( $time =~ /2019-01-02/ ) {
                    $content = path(__FILE__)->sibling('json/alloy/defect_search_all.json')->slurp;
                } elsif ( $time =~ /2019-01-03/ ) {
                    $content = path(__FILE__)->sibling('json/alloy/defect_search_multiple.json')->slurp;
                } else {
                    $content = path(__FILE__)->sibling('json/alloy/defect_search.json')->slurp;
                }
            } else {
                $content = path(__FILE__)->sibling('json/alloy/inspect_search.json')->slurp;
            }
        }
    } else {
        if ( $call eq 'reference/value-type' ) {
            $content = path(__FILE__)->sibling('json/alloy/reference_value_type.json')->slurp;
        } elsif ( $call eq 'source-type' ) {
            $content = path(__FILE__)->sibling('json/alloy/source_type.json')->slurp;
        } elsif ( $call eq 'source' ) {
            $content = path(__FILE__)->sibling('json/alloy/source.json')->slurp;
        } elsif ( $call eq 'resource/3027029/parents' ) {
            $content = '{ "details": { "parents": [] } }';
        } elsif ( $call eq 'resource/4947504/parents' ) {
            $content = '{ "details": { "parents": [ {"actualParentSourceTypeId": 1001181, "parentResId": 3027030 } ] } }';
        } elsif ( $call eq 'resource/3027029/versions' ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_versions.json')->slurp;
        } elsif ( $call eq 'resource/4947502/versions' ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_versions_4947502.json')->slurp;
        } elsif ( $call eq 'resource/3027030/versions' ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_versions_3027030.json')->slurp;
        } elsif ( $call eq 'resource/3027031/versions' ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_versions_3027031.json')->slurp;
        } elsif ( $call eq 'resource/3027029/full?systemVersion=272125' ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_3027029_v272125.json')->slurp;
        } elsif ( $call eq 'resource/3027030/full?systemVersion=271881' ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_3027030_v271881.json')->slurp;
        } elsif ( $call eq 'resource/3027031/full?systemVersion=271883' ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_3027031_v271883.json')->slurp;
        } elsif ( $call eq 'resource/1' ) {
            $content = '{ "sourceTypeId": 800 }';
        } elsif ( $call eq 'source-type/800/linked-source-types' ) {
            $content = path(__FILE__)->sibling('json/alloy/linked_source_types.json')->slurp;
        } elsif ( $call eq 'projection/point' ) {
            $content = '{ "x": 1, "y": 2 }';
        } elsif ( $call =~ m#resource/[0-9]*/parents# ) {
            $content = '{ "details": { "parents": [] } }';
        } elsif ( $call =~ m#resource/[0-9]*/versions# ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_versions_all.json')->slurp;
        } elsif ( $call eq 'resource/12345/full' ) {
            $content = '{ "resourceId": 12345, "values": [ { "attributeId": 1013262, "value": "Original text" } ], "version": { "currentSystemVersionId": 8001, "resourceSystemVersionId": 8000 } }';
        } else {
            $content = $responses{$call};
        }
    }

    $content ||= '[]';

    my $result = decode_json(encode_utf8($content));
    return $result;
});

subtest "create basic problem" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request( 
        POST => '/requests.json', 
        jurisdiction_id => 'dummy',
        api_key => 'test',
        service_code => 'Kerbs_Missing',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[title]' => '1',
        'attribute[report_url]' => 'http://localhost/1',
        'attribute[asset_resource_id]' => 1,
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Kerbs_Missing',
        'attribute[fixmystreet_id]' => 1,
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply $sent,
    {
    attributes =>         {
        1001546 => [
            {
                command => "add",
                resourceId => 1
            }
        ],
        1001825 => [
            {
                command => "add",
                resourceId => 708823
            }
        ],
        1009855 => 1,
        1009856 => "FixMyStreet",
        1009857 => "Request for Service",
        1009858 => [ { resourceId => 6183644, command => "add" } ],
        1009859 => 1,
        1009860 => "description",
        1009861 => "2014-01-01T12:00:00Z"
    },
    geoJson => {
        coordinates => [
            1,
            2
        ],
        type => "Point"
    },
    networkReference => undef,
    parents => {
        1009847 => [
            1
        ]
    },
    sourceId => 2590
    }
    , 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';

};

subtest "create problem with no resource_id" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request( 
        POST => '/requests.json', 
        jurisdiction_id => 'dummy',
        api_key => 'test',
        service_code => 'Kerbs_Missing',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[title]' => '1',
        'attribute[report_url]' => 'http://localhost/1',
        'attribute[asset_resource_id]' => '',
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Kerbs_Missing',
        'attribute[fixmystreet_id]' => 1,
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply $sent,
    {
    attributes =>         {
        1001546 => [
            {
                command => "add",
                resourceId => 1
            }
        ],
        1001825 => [
            {
                command => "add",
                resourceId => 708823
            }
        ],
        1009855 => 1,
        1009856 => "FixMyStreet",
        1009857 => "Request for Service",
        1009858 => [ { resourceId => 6183644, command => "add" } ],
        1009859 => 1,
        1009860 => "description",
        1009861 => "2014-01-01T12:00:00Z"
    },
    geoJson => {
        coordinates => [
            1,
            2
        ],
        type => "Point"
    },
    networkReference => undef,
    parents => {},
    sourceId => 2590
    }
    , 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';

};

subtest "check fetch updates" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=dummy&start_date=2019-01-01T00:00:00Z&end_date=2019-03-01T02:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        status => 'investigating',
        service_request_id => '3027029',
        description => 'This is a customer response',
        updated_datetime => '2019-01-01T00:32:40Z',
        update_id => '271882',
        media_url => '',
    },
    {
        status => 'investigating',
        service_request_id => '3027030',
        description => '',
        updated_datetime => '2019-01-01T01:42:40Z',
        update_id => '271883',
        media_url => '',
    },
    {
        status => 'not_councils_responsibility',
        service_request_id => '3027031',
        description => '',
        updated_datetime => '2019-02-19T02:42:40Z',
        update_id => '271884',
        media_url => '',
        external_status_code => 4281525,
    },
    {
        status => 'fixed',
        service_request_id => '4947502',
        description => '',
        updated_datetime => '2019-02-19T09:11:08Z',
        update_id => '271877',
        media_url => '',
        fixmystreet_id => '10034',
    } ], 'correct json returned';
};

subtest "check fetch multiple updates" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=dummy&start_date=2019-01-03T00:00:00Z&end_date=2019-03-03T02:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        status => 'not_councils_responsibility',
        service_request_id => '3027031',
        description => '',
        updated_datetime => '2019-02-19T02:42:40Z',
        update_id => '271884',
        media_url => '',
        external_status_code => 4281525,
    },
    {
        status => 'action_scheduled',
        service_request_id => '4947502',
        description => '',
        updated_datetime => '2019-01-03T09:12:18Z',
        update_id => '271877',
        media_url => '',
        fixmystreet_id => '10034',
        external_status_code => 4281523,
    },
    {
        status => 'action_scheduled',
        service_request_id => '3027030',
        description => '',
        updated_datetime => '2019-01-03T09:11:08Z',
        update_id => '271884',
        media_url => '',
        external_status_code => 4281523,
    },
], 'correct json returned';
};

subtest "create comment" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request( 
        POST => '/servicerequestupdates.json', 
        jurisdiction_id => 'dummy',
        api_key => 'test',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'This is an update',
        service_request_id => 12345,
        update_id => 999,
        status => 'OPEN',
        updated_datetime => '2019-04-17T14:39:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply $sent,
    {
    attributes =>         {
        1013262 => "Original text
Customer update at 2019-04-17 14:39:00
This is an update"
    },
    systemVersionId => 8000
    }
    , 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "update_id" => 8011
        } ], 'correct json returned';

};

subtest "check fetch problem" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
      GET => '/requests.json?jurisdiction_id=dummy&start_date=2019-01-02T00:00:00Z&end_date=2019-01-01T02:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [{
      long => 1,
      requested_datetime => "2019-01-02T11:29:16Z",
      service_code => "Shelter Damaged",
      updated_datetime => "2019-01-02T11:29:16Z",
      service_name => "Shelter Damaged",
      address_id => "",
      lat => 2,
      description => "test",
      service_request_id => 4947505,
      zipcode => "",
      media_url => "",
      status => "investigating",
      address => ""
   },
   {
      address_id => "",
      lat => 2,
      service_request_id => 4947597,
      description => "fill",
      service_name => "Grit Bin - empty/refill",
      status => "fixed",
      media_url => "",
      address => "",
      zipcode => "",
      requested_datetime => "2019-01-02T14:44:53Z",
      long => 1,
      updated_datetime => "2019-01-02T14:44:53Z",
      service_code => "Grit Bin - damaged/replacement",
      service_code => "Grit Bin - empty/refill"
   }], "correct json returned";
};

subtest "check fetch service description" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services.json?jurisdiction_id=dummy',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        service_code => 'Bus Stops_Shelter Damaged',
        service_name => "Shelter Damaged",
        description => "Shelter Damaged",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Bus Stops"
    },
    {
        service_code => 'Bus Stops_Sign/Pole Damaged',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Bus Stops",
        service_name => "Sign/Pole Damaged",
        description => "Sign/Pole Damaged"
    },
    {
        service_code => 'Drain Covers_Broken / Missing',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Drain Covers",
        service_name => "Broken / Missing",
        description => "Broken / Missing"
    },
    {
        service_code => 'Drain Covers_Loose / Raised/Sunken',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Drain Covers",
        service_name => "Loose / Raised/Sunken",
        description => "Loose / Raised/Sunken"
    },
    {
        service_code => 'Highway Bridges_Highway Bridges - Damaged/Unsafe',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Highway Bridges",
        service_name => "Highway Bridges - Damaged/Unsafe",
        description => "Highway Bridges - Damaged/Unsafe"
    },
    {
        service_code => 'Kerbs_Damaged/Loose',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Kerbs",
        service_name => "Damaged/Loose",
        description => "Damaged/Loose"
    },
    {
        service_code => 'Kerbs_Missing',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Kerbs",
        service_name => "Missing",
        description => "Missing"
    } ], 'correct json returned';
};

subtest "check fetch service metadata" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services/Highway%20Bridges_Highway%20Bridges%20-%20Damaged/Unsafe.json?jurisdiction_id=dummy',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    {
        service_code => "Highway Bridges_Highway Bridges - Damaged/Unsafe",
        attributes => [
          {
            variable => 'false',
            code => "easting",
            datatype => "number",
            required => 'true',
            datatype_description => '',
            order => 1,
            description => "easting",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "northing",
            datatype => "number",
            required => 'true',
            datatype_description => '',
            order => 2,
            description => "northing",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "fixmystreet_id",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 3,
            description => "external system ID",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "report_url",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 4,
            description => "Report URL",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "title",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 5,
            description => "Title",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "description",
            datatype => "text",
            required => 'true',
            datatype_description => '',
            order => 6,
            description => "Description",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "category",
            datatype => "text",
            required => 'true',
            datatype_description => '',
            order => 7,
            description => "Category",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "asset_resource_id",
            datatype => "text",
            required => 'true',
            datatype_description => '',
            order => 8,
            description => "Asset resource ID",
            automated => 'hidden_field',
          },
          {
            variable => 'true',
            code => "1010927",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 9,
            description => "FMS Contact",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "emergency",
            datatype => "text",
            required => 'false',
            datatype_description => '',
            order => 10,
            description => "This is an emergency",
          },
        ]
    }, 'correct json returned';
};

restore_time();
done_testing;
