use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;
use JSON::MaybeXS;
use Path::Tiny;

my $pt = Test::MockModule->new('Open311::Endpoint::Integration::UK::Bristol::Passthrough');
$pt->mock(endpoint => sub { '' });

my $expected_update_post = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <update_id>2002</update_id>
  </request_update>
</service_request_updates>
XML

my $ua = Test::MockModule->new('LWP::UserAgent');
$ua->mock(post => sub {
    my $args = $_[2];
    is $args->{service_code}, undef;
    return HTTP::Response->new(200, 'OK', [], $expected_update_post);
});

use_ok 'Open311::Endpoint::Integration::UK::Bristol::Passthrough';

my $endpoint = Open311::Endpoint::Integration::UK::Bristol::Passthrough->new;

subtest 'POST update' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.xml',
        api_key => 'test',
        service_code => 'SE01',
        service_request_id => 1001,
        update_id => 123,
        # first_name => 'Bob',
        # last_name => 'Mould',
        description => 'Update here',
        status => 'OPEN',
        updated_datetime => '2016-09-01T15:00:00Z',
        # media_url => 'http://example.org/',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is $res->content, $expected_update_post;
};

done_testing;
