use strict;
use warnings;

use Test::More;
use Test::MockModule;
use JSON::MaybeXS;

BEGIN { $ENV{TEST_MODE} = 1; }

my $lwp = Test::MockModule->new('LWP::UserAgent');
my @payloads;
$lwp->mock(request => sub {
    my ($ua, $req) = @_;
    push @payloads, decode_json($req->content);
    return HTTP::Response->new(200, 'OK', [], '1001');
});

my $endpoint_config = {
    endpoint_url => 'http://example.com/',
    username => 'user',
    password => 'pass',
    category_mapping => {
        FallenTree => {
            name => "Fallen/damaged tree or branch",
        },
    },
};

my $merton_ezytreev_open311_mock = Test::MockModule->new('Open311::Endpoint::Integration::UK::Merton::Ezytreev');
$merton_ezytreev_open311_mock->mock(endpoint_config => sub { $endpoint_config });

my $ezytreev_mock = Test::MockModule->new('Integrations::Ezytreev');
$ezytreev_mock->mock(config => sub { $endpoint_config });

use Open311::Endpoint::Integration::UK::Merton::Ezytreev;

my $endpoint = Open311::Endpoint::Integration::UK::Merton::Ezytreev->new;

my @request_data = (
    POST => '/requests.json',
    api_key => 'test',
    service_code => 'FallenTree',
    first_name => 'Bob',
    last_name => 'Mould',
    description => "This is the details",
    lat => 51,
    long => -1,
    'attribute[easting]' => 100,
    'attribute[northing]' => 100,
    'attribute[fixmystreet_id]' => 1001,
    'attribute[description]' => "",
    'attribute[report_url]' => "",
    'attribute[title]' => "",
);

subtest "POST service request payload includes custom fields" => sub {
    my $res = $endpoint->run_test_request(@request_data);
    ok $res->is_success, 'valid request'
        or diag $res->content;
    my $payload = $payloads[0];
    ok $payload->{EnquiryMethod}, 'includes EnquiryMethod';
    ok $payload->{EnquiryOrigion}, 'includes EnquiryOrigion';
};

done_testing;
