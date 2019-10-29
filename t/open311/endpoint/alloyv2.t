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

package Integrations::AlloyV2::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling("alloyv2.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("alloyv2.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::AlloyV2::Dummy');
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

my $integration = Test::MockModule->new('Integrations::AlloyV2');
$integration->mock('api_call', sub {
    my ($self, %args) = @_;
    my $call = $args{call};
    my $params = $args{params};
    my $body = $args{body};

    my $content = '[]';
    push @calls, $call;
    if ( $body ) {
        push @sent, $body;
    } else {
        if ( $call eq 'design/designs_enquiryInspectionRFS1001181_5d3245c5fe2ad806f8dfbaf6' ) {
            $content = path(__FILE__)->sibling('json/alloyv2/design_rfs.json')->slurp;
        } else {
            $content = $responses{$call};
        }
    }

    $content ||= '[]';

    my $result = decode_json(encode_utf8($content));
    return $result;
});

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
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 7,
            description => "Category",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "asset_resource_id",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 8,
            description => "Asset resource ID",
            automated => 'hidden_field',
          },
          {
            variable => 'false',
            code => "emergency",
            datatype => "text",
            required => 'false',
            datatype_description => '',
            order => 9,
            description => "This is an emergency",
          },
        ]
    }, 'correct json returned';
};

restore_time();
done_testing;
