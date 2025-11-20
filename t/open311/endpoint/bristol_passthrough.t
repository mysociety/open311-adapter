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
    if ($args->{update_id} == 456) {
      is $args->{description}, 'No update text';
    } else {
      is $args->{description}, 'Update here';
    }
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

subtest 'POST update' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.xml',
        api_key => 'test',
        service_code => 'SE01',
        service_request_id => 1001,
        update_id => 456,
        description => '',
        status => 'OPEN',
        updated_datetime => '2016-09-01T15:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is $res->content, $expected_update_post;
};

my $returned_update_get = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <update_id>2003</update_id>
    <service_request_id>1001</service_request_id>
    <status>OPEN</status>
    <description>This is an update</description>
    <updated_datetime>2025-09-22T09:00:00Z</updated_datetime>
  </request_update>
  <request_update>
    <update_id>2004</update_id>
    <service_request_id>1002</service_request_id>
    <status>OPEN</status>
    <description>A citizen has provided a follow-up to the original enquiry.</description>
    <updated_datetime>2025-09-22T10:00:00Z</updated_datetime>
  </request_update>
</service_request_updates>
XML

my $expected_update_get = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <description>This is an update</description>
    <media_url></media_url>
    <service_request_id>1001</service_request_id>
    <status>open</status>
    <update_id>2003</update_id>
    <updated_datetime>2025-09-22T09:00:00Z</updated_datetime>
  </request_update>
</service_request_updates>
XML

$ua->mock(get => sub {
    my $args = $_[2];
    is $args->{service_code}, undef;
    return HTTP::Response->new(200, 'OK', [], $returned_update_get);
});

subtest 'GET updates' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?api_key=test&start_date=2019-10-23T00:00:00Z&end_date=2019-10-24T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is $res->content, $expected_update_get;
};

done_testing;
