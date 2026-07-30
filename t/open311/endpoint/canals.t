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


done_testing;
