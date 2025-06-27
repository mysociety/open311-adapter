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

    if ($req->uri =~ /login/) {
        ok $req->uri =~ /dummy\/api/, 'api url read from config';
        return HTTP::Response->new(200, 'OK', [], encode_json({ 'userId' => 'User-12345', 'access_token' => 'OpenSesame' }));
    } elsif ($req->uri =~ /Insert/) {
        ok $req->header('.aspxauth') eq 'OpenSesame', 'Authorisation header set';
        is_deeply decode_json($req->content), decode_json(path(__FILE__)->sibling("/json/cams/report.json")->slurp), 'Report details filled';
        return HTTP::Response->new(200, 'OK', [], '12345');
    }
});

sub _build_config_file { path(__FILE__)->sibling("buckinghamshire_cams.yml")->stringify };

package Open311::Endpoint::Integration::Cams::Dummy;
use Moo;

extends 'Open311::Endpoint::Integration::Cams';

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

BEGIN { $ENV{TEST_MODE} = 1; }

my $bucks_endpoint = Open311::Endpoint::Integration::Cams::Dummy->new(
    jurisdiction_id => 'buckinghamshire_cams',
    config_file => path(__FILE__)->sibling("buckinghamshire_cams.yml")->stringify,
    );

subtest "GET Service List" => sub {
    my $res = $bucks_endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
};

subtest "Check services structure" => sub {
    my @services = $bucks_endpoint->services;
    ok scalar @services == 3, 'Three services received';
    for my $test (
        {
            service_code => '9',
            service_name => 'Alignment/Path Off Line',
        },
        {
            service_code => 'I273',
            service_name => 'Bridge/Missing',
        },
        {
            service_code => 'I274',
            service_name => 'Damaged Bridge',
        },
    ) {
        my $contact = shift @services;
        ok $contact->{service_code} eq $test->{service_code}, 'Correct service code';
        ok $contact->{service_name} eq $test->{service_name}, 'Correct service name';
        ok $contact->{group} eq 'Public Rights of Way', 'Correct group';
        my @hidden_fields = ('AdminArea', 'LinkCode', 'LinkType');
        for my $attribute (grep { $_->{automated} eq 'hidden_field' } @{$contact->{attributes}}) {
            ok $attribute->code eq shift @hidden_fields;
        };
    };
};

subtest "POST report" => sub {

    my $uuid = Test::MockModule->new('Data::UUID');
    $uuid->mock(create => sub { return 'random uuid' });

    my $res = $bucks_endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'buckinghamshire_cams',
        api_key => 'api-key',
        service_code => 'I274',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'title: Bridge damaged detail: Handrail has come off',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'Handrail has come off',
        'attribute[title]' => 'Bridge damaged',
        'attribute[report_url]' => 'http://localhost/1',
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Damaged Bridge',
        'attribute[fixmystreet_id]' => 1,
        'attribute[AdminArea]' => '081',
        'attribute[LinkCode]' => 'TLE/43418',
        'attribute[LinkType]' => '2'
    );

    is $res->code, 200, 'Report submitted ok';

};

done_testing;
