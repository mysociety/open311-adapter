package Integrations::Rest::Dummy;
use Path::Tiny;
use Moo;
use Test::More;
use Test::MockModule;
use JSON::MaybeXS qw(encode_json decode_json);

extends 'Integrations::Rest';

my $lwp = Test::MockModule->new('LWP::UserAgent');

$lwp->mock(request => sub {
    my ($ua, $req) = @_;
    if ($req->uri =~ /Token/) {
        like $req->uri, qr/example\.com\/api\//, 'api url read from config';
        return HTTP::Response->new(200, 'OK', [], encode_json({ 'access_token' => 'OpenSesame' }));
    } elsif ($req->uri =~ /Incidents$/) {
        is $req->header('Authorization'),'Bearer OpenSesame', 'Authorisation header set';
        return HTTP::Response->new(200, 'OK', [], encode_json({ 'id' => 'incident-12345' }));
    } elsif ($req->uri =~ /Contacts/) {
        is $req->header('Authorization'),'Bearer OpenSesame', 'Authorisation header set';
        return HTTP::Response->new(200, 'OK', [], encode_json({ 'id' => 'user-236' }));
    } elsif ($req->uri =~ /Incidents\/incident-12345\/incidents_case/) {
        is $req->header('Authorization'),'Bearer OpenSesame', 'Authorisation header set';
        return HTTP::Response->new(200, 'OK', [], encode_json({ 'related_record' => { 'id' => 'case-3456' } }));
    }
});

sub _build_config_file { path(__FILE__)->sibling("canals.yml")->stringify };

package Open311::Endpoint::Integration::Sugar::Dummy;
use Path::Tiny;
use Moo;
use HTTP::Response;
use HTTP::Headers;

extends 'Open311::Endpoint::Integration::Sugar';

has integration_class => (
    is => 'ro',
    default => 'Integrations::Rest::Dummy',
);

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Path::Tiny;
use Open311::Endpoint::Service::UKCouncil;
use JSON::MaybeXS qw(encode_json decode_json);

BEGIN { $ENV{TEST_MODE} = 1; }

my $canals_endpoint = Open311::Endpoint::Integration::Sugar::Dummy->new(
    jurisdiction_id => 'canals_sugar',
    config_file => path(__FILE__)->sibling("canals.yml")->stringify,
    );

subtest "GET Service List" => sub {
    my $res = $canals_endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
};

subtest "Check user login" => sub {
    my $res = $canals_endpoint->_do_login('Test', 'User', 'test@example.com');
    ok $canals_endpoint->access_token, 'OpenSesame';
};

subtest "POST report" => sub {
    my $res = $canals_endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'canals',
        api_key => 'api-key',
        media_url => [],
        service_code => 'Aqueduct_Access_Issues',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'Aqueduct is blocked by tree',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'Aqueduct is blocked by tree',
        'attribute[title]' => 'Aqueduct by Potters Bridge is blocked',
        'attribute[report_url]' => 'http://localhost/1',
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Access Issues (CRT: Aqueduct)',
        'attribute[fixmystreet_id]' => 1,
    );

    is $res->code, 200, 'Report submitted ok';
    is_deeply decode_json($res->content), [ { service_request_id => 'incident-12345--case-3456' } ], 'Id from the Case record';
};

done_testing;
