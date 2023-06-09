package Integrations::Abavus::Dummy;
use Path::Tiny;
use Moo;
use HTTP::Response;
use HTTP::Headers;
use Test::More;
use Test::MockModule;
use JSON::MaybeXS qw(encode_json decode_json);
use URI;

extends 'Integrations::Abavus';

my $lwp = Test::MockModule->new('LWP::UserAgent');
my $lwp_counter = 0;

$lwp->mock(request => sub {
    my ($ua, $req) = @_;

    my %put_requests = (
        'http://localhost/api/serviceRequest/questions/1?questionCode=EXPLAIN_ABANDONED_SITE_646941_I&answer=Car%20abandoned%20for%20a%20week' => 1,
        'http://localhost/api/serviceRequest/questions/1?questionCode=ABANDONED_SITE_FMS_REPORT_ID_648132_I&answer=1' => 1,
        'http://localhost/api/serviceRequest/questions/1?questionCode=ABANDONED_SITE_FULL_NAME_646942_I&answer=Bob%20Mould' => 1,
        'http://localhost/api/serviceRequest/questions/1?questionCode=ABANDONED_SITE_SUMMERISE_646538_I&answer=Abandoned%20Cortina' => 1,
        'http://localhost/api/serviceRequest/questions/1?questionCode=ABANDONED_SITE_EMAIL_646943_I&answer=test@example.com' => 1,
        'http://localhost/api/serviceRequest/questions/1?questionCode=ABANDONED_ISSUE_TYPE_646538_I&answer=ABANDONED_916276_A' => 1,
        'http://localhost/api/serviceRequest/questions/1?questionCode=ABANDONED_SITE_PHOTOS_646943_I&answer=one.jpg,two.jpg' => 1,
    );

    if ($req->uri =~ /serviceRequest$/) {
        is $req->headers->{ipublickey}, 'api-key';
        is $req->uri, 'http://localhost/api/serviceRequest';
        my $content = decode_json($req->content);
        is $content->{serviceRequest}->{submissionDate}, "01-MAY-2023 13:00:00";
        is $content->{serviceRequest}->{form}->{code}, 'ABANDONED_17821_C';
        is $content->{serviceRequest}->{location}->{latitude}, '50';
        is $content->{serviceRequest}->{location}->{longitude}, '0.1';
        return HTTP::Response->new(200, 'OK', [], encode_json({"result" => 1, "id" => 1}));
    } else {
        is $req->method, 'POST', "Correct method used";
        is $put_requests{$req->uri}, 1, "Call formed correctly";
        ++$lwp_counter;
        return HTTP::Response->new(200, 'OK', [], encode_json({"result" => 1, "id" => 1}));
    }
});

sub _build_config_file { path(__FILE__)->sibling("abavus.yml")->stringify };

package Open311::Endpoint::Integration::Abavus::Dummy;
use Path::Tiny;
use Moo;
use HTTP::Response;
use HTTP::Headers;

extends 'Open311::Endpoint::Integration::Abavus';

has integration_class => (
    is => 'ro',
    default => 'Integrations::Abavus::Dummy',
);

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Test::MockTime ':all';

use Open311::Endpoint;
use Path::Tiny;
use Open311::Endpoint::Integration::Abavus;
use Integrations::Abavus;
use Open311::Endpoint::Service::UKCouncil;
use LWP::UserAgent;

BEGIN { $ENV{TEST_MODE} = 1; }

my $bucks_endpoint = Open311::Endpoint::Integration::Abavus::Dummy->new(
    jurisdiction_id => 'bucks_abavus',
    config_file => path(__FILE__)->sibling("abavus.yml")->stringify,
    );

subtest "Check services structure" => sub {
    my @services = $bucks_endpoint->services;

    is scalar @services, 6, "Six categories found";
    my %count_services;
    for my $service(@services) {
        $count_services{$service->{group}}++;
    };
    is $count_services{'Abandoned vehicles'} == 1 && $count_services{'Bus stop/shelter issue'} == 5, 1, "Categories are grouped";

    my @service = grep { $_->{service_code} eq 'DISPLAY_ISSUE_17821_C' } @services;
    die "Unexpected duplication of service codes" if @service != 1;

    is $service[0]->{description} eq 'Electric info display broken/incorrect', 1, "Description and code match";

    my @extra = grep {$_->{code} eq 'DISPLAY_ISSUE_TYPE_646538_I' } @{$service[0]->{attributes}};
    die "Unexpected duplication of extra data codes" if @extra != 1;

    is $extra[0]->{description} eq 'Incorrect or broken', 1, "Dropdown extra question title correct";
    is $extra[0]->{datatype} eq 'singlevaluelist', 1, "Dropdown correct type";
    is $extra[0]->{required} == 1, 1, "Required set";

    my $dropdown_values = $extra[0]->{values};
    is $dropdown_values->{DISPLAY_916276_A} eq 'Incorrect', 1, "Dropdown 1 correct";
    is $dropdown_values->{DISPLAY_916277_A} eq 'Broken', 1, "Dropdown 2 correct";

    @extra = grep {$_->{code} eq 'DISPLAY_CONTACT_646539_I' } @{$service[0]->{attributes}};
    die "Unexpected duplication of extra data codes" if @extra != 1;

    is $extra[0]->{datatype} eq 'text', 1, "Text correct type";
    is $extra[0]->{required} == 0, 1, "Required not set";
};

subtest "GET Service List" => sub {
    my $res = $bucks_endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
};

subtest "POST report" => sub {
    set_fixed_time('2023-05-01T12:00:00Z');
    my $res = $bucks_endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'bucks_abavus',
        api_key => 'api-key',
        service_code => 'ABANDONED_17821_C',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'Car abandoned for a week',
        media_url => ['one.jpg','two.jpg'],
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[title]' => 'Abandoned Cortina',
        'attribute[report_url]' => 'http://localhost/1',
        'attribute[asset_resource_id]' => '39dhd38dhdkdnxj',
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Abandoned vehicle',
        'attribute[fixmystreet_id]' => 1,
        'attribute[ABANDONED_ISSUE_TYPE_646538_I]' => 'ABANDONED_916276_A',
        );
    is $lwp_counter, 7, "Seven fields added";
    is $res->code, 200;
};

done_testing;
