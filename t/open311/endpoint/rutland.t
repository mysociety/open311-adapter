package Mock::Response;

use Moo;
use Encode;
use Types::Standard ':all';

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

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::MockTime ':all';

use Open311::Endpoint;
use Data::Dumper;
use JSON::MaybeXS;

use Open311::Endpoint::Integration::UK;
use Integrations::SalesForce::Rutland;

my $endpoint = Open311::Endpoint::Integration::UK->new;

my %responses = (
    'new_report' => '[{ "Id": "12345" }]',
    'GET /services/apexrest/FixMyStreetInfosummary' => '{
        "title": "Summary Categories",
        "CategoryInformation": [
            {
                "serviceid": "a096E000007pbxWQAQ",
                "name_code": "POT",
                "name": "Fly Tipping"
            },
            {
                "serviceid": "a096E000007pbwiQAA",
                "name_code": "RC08",
                "name": "Street Furniture"
            }
        ]
    }',
    'GET /services/apexrest/FixMyStreetInfoid=POT' => '{
        "title": "POT",
        "fieldInformation": [
            {
                "optionsList": [],
                "name": "extra",
                "length": "1000",
                "label": "Additional Information",
                "fieldType": "text"
            }
        ]
    }',
    'GET /services/apexrest/FixMyStreetInfoid=a096E000007pbxWQAQ' => '{
        "title": "POT",
        "fieldInformation": [
            {
                "optionsList": [],
                "name": "extra",
                "length": "1000",
                "label": "Additional Information",
                "fieldType": "text"
            }
        ]
    }',
    'GET /services/apexrest/FixMyStreetInfoid=RC_08' => '{
        "title": "RC08",
        "fieldInformation": [
            {
                "optionsList": ["One", "Two", "Don´t know"],
                "name": "pot_type",
                "length": "1000",
                "label": "Additional Information",
                "fieldType": "text"
            }
        ]
    }',
);

my @sent;

my $integration = Test::MockModule->new('Integrations::SalesForce::Rutland');
$integration->mock('_get_response', sub {
    my ($self, $req) = @_;
    my $key = sprintf '%s %s%s', $req->method, $req->uri->path, $req->uri->query || '';
    my $content = '[]';
    if ( $key eq 'POST /services/apexrest/FixMyStreet' ) {
        push @sent, $req->content;
        $content = $responses{new_report};
    } else {
        $content = $responses{$key};
    }

    return Mock::Response->new( content => $content );
});

subtest "create basic problem" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request( 
        POST => '/requests.json', 
        jurisdiction_id => 'rutland',
        api_key => 'test',
        service_code => 'POT',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[external_id]' => '1',
        'attribute[title]' => '1',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply decode_json($sent),
    [{
        "detail__c" => "description",
        "description__c" => "description",
        "updated_datetime__c" => "2014-01-01T12:00:00+0000",
        "status__c" => "open",
        "lat__c" => 50.0,
        "service_request_id__c" => 1,
        "Service_Area__c" => "POT",
        "requested_datetime__c" => "2014-01-01T12:00:00+0000",
        "requestor_name__c" => "Bob Mould",
        "title__c" => "1",
        "interface_used__c" => "Web interface",
        "long__c" => 0.1,
        "contact_name__c" => "Bob Mould",
        "contact_email__c" => 'test@example.com',
        "agency_sent_datetime__c" => "2014-01-01T12:00:00+0000",
        "agency_responsible__c" => "Rutland County Council"
    }] , 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';

};

subtest "create problem with extra categories" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'rutland',
        api_key => 'test',
        service_code => 'POT',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[external_id]' => '1',
        'attribute[title]' => '1',
        'attribute[extra]' => 'extra_attribute',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply decode_json($sent),
    [{
        detail__c => "description",
        description__c => "description",
        updated_datetime__c => "2014-01-01T12:00:00+0000",
        status__c => "open",
        lat__c => 50.0,
        service_request_id__c => 1,
        Service_Area__c => "POT",
        requested_datetime__c => "2014-01-01T12:00:00+0000",
        requestor_name__c => "Bob Mould",
        title__c => "1",
        interface_used__c => "Web interface",
        long__c => 0.1,
        contact_name__c => "Bob Mould",
        contact_email__c => 'test@example.com',
        agency_sent_datetime__c => "2014-01-01T12:00:00+0000",
        agency_responsible__c => "Rutland County Council",
        extra => "extra_attribute"
    }] , 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';

};

subtest "create problem with extra list categories" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'rutland',
        api_key => 'test',
        service_code => 'RC_08',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[pot_type]' => 'Don´t know',
        'attribute[external_id]' => '1',
        'attribute[title]' => '1',
        'attribute[description]' => 'description',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply decode_json($sent),
    [{
        detail__c => "description",
        description__c => "description",
        updated_datetime__c => "2014-01-01T12:00:00+0000",
        status__c => "open",
        lat__c => 50.0,
        service_request_id__c => 1,
        Service_Area__c => "RC_08",
        requested_datetime__c => "2014-01-01T12:00:00+0000",
        requestor_name__c => "Bob Mould",
        title__c => "1",
        interface_used__c => "Web interface",
        long__c => 0.1,
        contact_name__c => "Bob Mould",
        contact_email__c => 'test@example.com',
        agency_sent_datetime__c => "2014-01-01T12:00:00+0000",
        agency_responsible__c => "Rutland County Council",
        pot_type => "Don´t know"
    }] , 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';

};

subtest "create problem with multiple photos" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'rutland',
        api_key => 'test',
        service_code => 'POT',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[external_id]' => '1',
        'attribute[title]' => '1',
        media_url => 'http://photo1.com',
        media_url => 'http://photo2.com',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply decode_json($sent),
    [{
        detail__c => "description",
        description__c => "description",
        updated_datetime__c => "2014-01-01T12:00:00+0000",
        status__c => "open",
        lat__c => 50.0,
        service_request_id__c => 1,
        Service_Area__c => "POT",
        requested_datetime__c => "2014-01-01T12:00:00+0000",
        requestor_name__c => "Bob Mould",
        title__c => "1",
        photos => ["http://photo1.com", "http://photo2.com"],
        interface_used__c => "Web interface",
        long__c => 0.1,
        contact_name__c => "Bob Mould",
        contact_email__c => 'test@example.com',
        agency_sent_datetime__c => "2014-01-01T12:00:00+0000",
        agency_responsible__c => "Rutland County Council"
    }] , 'correct json sent for mulitple photos';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';

};

subtest "check fetch service description" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services.json?jurisdiction_id=rutland',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        service_code => 'a096E000007pbxWQAQ',
        service_name => "Fly Tipping",
        description => "Fly Tipping",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => ""
    },
    {
        service_code => 'a096E000007pbwiQAA',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "",
        service_name => "Street Furniture",
        description => "Street Furniture"
    } ], 'correct json returned';
};

subtest "check fetch service metadata" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services/a096E000007pbxWQAQ.json?jurisdiction_id=rutland',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    {
        service_code => "a096E000007pbxWQAQ",
        attributes => [
          {
            variable => 'false',
            code => "external_id",
            datatype => "number",
            required => 'true',
            datatype_description => '',
            order => 1,
            description => "external_id",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "title",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 2,
            description => "title",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "description",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 3,
            description => "description",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "closest_address",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 4,
            description => "closest_address",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "extra",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 5,
            description => "Additional Information",
          }
        ]
    }, 'correct json returned';
};

restore_time();
done_testing;
