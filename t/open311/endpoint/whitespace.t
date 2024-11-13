package SOAP::Result;
use Object::Tiny qw(method result fault);

package Integrations::Whitespace::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Whitespace';
sub _build_config_file { path(__FILE__)->sibling("whitespace.yml")->stringify }

package Open311::Endpoint::Integration::Whitespace::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Whitespace';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'whitespace_dummy';
    $args{config_file} = path(__FILE__)->sibling("whitespace.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Whitespace::Dummy');

package main;

use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;
use JSON::MaybeXS;
use SOAP::Lite;

my $lwp = Test::MockModule->new('LWP::UserAgent');
$lwp->mock(get => sub {
    return HTTP::Response->new(200, 'OK', [], 'Hello' . $_[1]);
});

# This is called when a test below makes a SOAP call, along with the data
# to be passed via SOAP to the server. We check the values here, then pass
# back a mocked result.
my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    my ($cls, $method, @args) = @_;

    if ($method eq 'CreateWorksheet') {
        my $args = $args[0];

        my %params = map { $_->name => $_->value } ${$args->value}->value;
        is $params{Uprn}, 1000001, 'Uprn correct';
        is $params{ServiceId}, '289', 'ServiceId correct';
        is $params{WorksheetReference}, 2000123, 'WorksheetReference correct';
        is $params{WorksheetMessage}, 'This is the details', 'Description correct';

        my %service_property_inputs = map { $_->value } map { ${$_->value}->value } ${$params{ServicePropertyInputs}}->value->value;
        is $service_property_inputs{'79'}, 'No', 'AssistedYn correct';
        is $service_property_inputs{'80'}, 'Front of property', 'LocationOfContainers correct';

        my %service_item_inputs = map { $_->name => $_->value } ${${$params{ServiceItemInputs}}->value->value}->value->value;
        is $service_item_inputs{'ServiceItemId'}, '22', 'ServiceItemId correct';
        is $service_item_inputs{'ServiceItemQuantity'}, 1, 'ServiceItemQuantity correct';
        is $service_item_inputs{'ServiceItemName'}, '', 'ServiceItemName correct';

        return SOAP::Result->new(
            method => 'CreateWorksheet',
            result => { ErrorCode => "0", ErrorDescription => 'Success', WorksheetResponse => { anyType => ["242259", ""] } },
        );
    } else {
        die "Unknown method $method";
    }
});

use Open311::Endpoint::Integration::Whitespace::Dummy;

my $endpoint = Open311::Endpoint::Integration::Whitespace::Dummy->new;

subtest "GET services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), [
        {
            group        => "Waste",
            service_code => "missed_collection",
            description  => "Report missed collection",
            keywords     => "waste_only",
            type         => "realtime",
            service_name => "Report missed collection",
            metadata     => "true"
        }
    ], 'correct json returned';
};

subtest "GET service" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services/missed_collection.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), {
      "service_code" => "missed_collection",
      "attributes" => [
          { code => 'uprn', order => 1, required => 'false', variable => 'true', datatype => 'string', datatype_description => '', automated => 'hidden_field', description => 'UPRN reference' },
          { code => 'service_item_name', order => 2, required => 'false', variable => 'true', datatype => 'string', datatype_description => '', automated => 'hidden_field', description => 'Service item name' },
          { code => 'fixmystreet_id', order => 3, required => 'true', variable => 'false', datatype => 'string', datatype_description => '', automated => 'server_set', description => 'external system ID' },
          { code => 'assisted_yn', order => 4, required => 'false', variable => 'true', datatype => 'string', datatype_description => '', automated => 'hidden_field', description => 'Assisted collection (Yes/No)' },
          { code => 'location_of_containers', order => 5, required => 'false', variable => 'true', datatype => 'string', datatype_description => '', automated => 'hidden_field', description => 'Location of containers' },
          { code => 'location_of_letterbox', order => 6, required => 'false', variable => 'true', datatype => 'string', datatype_description => '', automated => 'hidden_field', description => 'Location of letterbox' },
          { code => 'quantity', order => 7, required => 'false', variable => 'true', datatype => 'string', datatype_description => '', automated => 'hidden_field', description => 'Number of containers' },
      ],
    }, 'correct json returned';
};

subtest "POST missed collection OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'missed_collection',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[uprn]' => 1000001,
        'attribute[fixmystreet_id]' => 2000123,
        'attribute[service_item_name]' => 'RES-180',
        'attribute[assisted_yn]' => 'No',
        'attribute[location_of_containers]' => 'Front of property',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '242259',
        } ], 'correct json returned';
};

done_testing;
