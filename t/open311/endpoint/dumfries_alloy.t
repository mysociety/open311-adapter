package Integrations::AlloyV2::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling('dumfries_alloy.yml')->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Dumfries';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dumfries_alloy';
    $args{config_file} = path(__FILE__)->sibling('dumfries_alloy.yml')->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::AlloyV2::Dummy');

package main;

use strict;
use warnings;
use utf8;

use Test::More;
use Test::MockModule;
use Test::MockTime ':all';
use Encode;
use JSON::MaybeXS;
use Path::Tiny;
use Data::Dumper;

BEGIN { $ENV{TEST_MODE} = 1; }

my (@sent);

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

my $lwp = Test::MockModule->new('LWP::UserAgent');
$lwp->mock('get', sub {
    my ($self, $url) = @_;
    return HTTP::Response->new(200, 'OK', [], '{}');
});

my $integration = Test::MockModule->new('Integrations::AlloyV2');
$integration->mock('api_call', sub {
    my ( $self, %args ) = @_;

    my $call    = $args{call};
    my $params  = $args{params};
    my $body    = $args{body};
    my $is_file = $args{is_file};

    my $content;

    if ($body) {
        push @sent, $body;

        if ( $call =~ m{^item$} && $body->{designCode} eq 'designs_contacts' ) {
            # Creating a contact
            $content = '{ "item": { "itemId": "contact_123" } }';
        } elsif ( $call =~ m{^item$} ) {
            # Creating new report
            $content = '{ "item": { "itemId": "report_456" } }';
        } elsif ( $call =~ m{aqs/query} ) {
            my $dodi_code = $body->{aqs}->{properties}->{dodiCode} || '';
            if ( $dodi_code eq 'designs_contacts' ) {
                # Searching for existing contact - return empty (doesn't exist)
                $content = '{ "page": 1, "results": [] }';
            } elsif ( $dodi_code eq 'designs_seReportedIssueList' ) {
                # Getting service whitelist
                $content = path(__FILE__)->sibling('json/alloyv2/dumfries/categories_search.json')->slurp;
            } else {
                $content = '{ "page": 1, "results": [] }';
            }
        } elsif ( $call =~ m{aqs/statistics} ) {
            # Statistics query - return count
            $content = '{ "page": 1, "pageSize": 20, "results": [{"value":{"attributeCode":"fake","value":5.0}}] }';
        }

    } else {
        if ( $call eq 'design/designs_serviceEnquiry' ) {
            # Getting the RFS design
            $content = path(__FILE__)->sibling('json/alloyv2/design_rfs.json')->slurp;
        } elsif ( $call =~ m{design/designs_seReportedIssueList} ) {
            # Getting service list design
            $content = '{ "design": { "code": "designs_seReportedIssueList" } }';
        } else {
            die "No handler found for API call $call";
        }
    }

    if ( !$content ) {
        warn 'No handler found for API call ' . $call;
        return decode_json('[]');
    }

    return decode_json( encode_utf8($content) );
});

subtest 'check services use Alloy IDs as service codes' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json?jurisdiction_id=dumfries_alloy'
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    my $services = decode_json($res->content);

    # Find the "Pothole" service under "Roads"
    my ($pothole_roads) = grep {
        $_->{service_name} eq 'Pothole' &&
        grep { $_ eq 'Roads' } @{$_->{groups}}
    } @$services;

    is $pothole_roads->{service_code}, '123a123',
        'Roads > Pothole uses ID from config as service code';

    # Find the "Pothole" service under "Pavements"
    my ($pothole_pavements) = grep {
        $_->{service_name} eq 'Pothole' &&
        grep { $_ eq 'Pavements' } @{$_->{groups}}
    } @$services;

    is $pothole_pavements->{service_code}, '456d456',
        'Pavements > Pothole uses different ID from config as service code';

    # Verify they're different even though they have the same name
    isnt $pothole_roads->{service_code}, $pothole_pavements->{service_code},
        'Same subcategory name in different groups gets different service codes';
};

subtest 'send new report to Alloy with contact and service_code' => sub {
    set_fixed_time('2025-12-03T12:00:00Z');

    @sent = ();

    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'dumfries_alloy',
        api_key => 'test',
        service_code => '123a123',  # Using the Alloy ID as service code
        address_string => '1 High Street',
        first_name => 'Test',
        last_name => 'User',
        email => 'test@example.com',
        phone => '07700900123',
        description => 'There is a large pothole',
        lat => '55.0611',
        long => '-3.6056',
        'attribute[description]' => 'There is a large pothole',
        'attribute[title]' => 'Pothole on High Street',
        'attribute[report_url]' => 'http://localhost/123',
        'attribute[category]' => 'Roads_Pothole',
        'attribute[fixmystreet_id]' => 123,
        'attribute[easting]' => 300000,
        'attribute[northing]' => 600000,
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    # Filter to only item creations (not AQS queries)
    my @items = grep { $_->{designCode} } @sent;

    # Should have created a contact first, then the report
    is scalar(@items), 2, 'created contact and report'
        or diag "Got " . scalar(@items) . " items:\n" . Dumper(\@items);

    my $contact_sent = $items[0];
    is $contact_sent->{designCode}, 'designs_contacts',
        'first call creates contact';

    my $report_sent = $items[1];

    # Find the contact attribute
    my ($contact_attr) = grep {
        $_->{attributeCode} eq 'attributes_defectsReporters'
    } @{$report_sent->{attributes}};

    ok $contact_attr, 'contact attribute present';
    is_deeply $contact_attr->{value}, ['contact_123'],
        'contact attribute contains created contact ID';

    # Find the service_code attribute
    my ($service_code_attr) = grep {
        $_->{attributeCode} eq 'attributes_serviceEnquiryReportedIssue'
    } @{$report_sent->{attributes}};

    ok $service_code_attr, 'service_code attribute present';
    is_deeply $service_code_attr->{value}, ['123a123'],
        'service_code attribute contains the Alloy ID';

    is_deeply decode_json($res->content),
        [ { service_request_id => 'report_456' } ],
        'correct json returned';

    restore_time();
};

done_testing;
