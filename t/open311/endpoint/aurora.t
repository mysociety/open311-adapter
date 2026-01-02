package Integrations::Aurora::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Aurora';
sub _build_config_file { path(__FILE__)->sibling("aurora.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Aurora';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("aurora.yml")->stringify;
    return $class->$orig(%args);
};

has integration_class => (is => 'ro', default => 'Integrations::Aurora::Dummy');

package main;

use strict;
use warnings;

use HTTP::Request::Common;
use HTTP::Response;
use JSON::MaybeXS;
use Path::Tiny;
use Test::MockModule;
use Test::More;
use Test::LongString;
use Web::Dispatch::Upload;

my $integration = Test::MockModule->new("Integrations::Aurora");
my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

BEGIN { $ENV{TEST_MODE} = 1; }

my $updates_list = path(__FILE__)->sibling("central_beds_aurora_update_files.xml")->slurp;
my $update_file = path(__FILE__)->sibling("central_beds_aurora_update_file.json")->slurp;


subtest "services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    my $services = decode_json($res->content);
    my $sorted_services = [ sort { $a->{service_code} cmp $b->{service_code}} @$services];
    is_deeply $sorted_services,
        [
            {
                service_code => 'potholes',
                service_name => 'Potholes',
                group => 'Roads',
                description => 'Potholes',
                keywords => '',
                type => 'realtime',
                metadata => 'true',
            },
            {
                service_code => 'trees',
                service_name => 'Trees',
                group => '',
                description => 'Trees',
                keywords => '',
                type => 'realtime',
                metadata => 'true',
            },
        ];
};

subtest "post_service_request" => sub {
    my $get_contact_email;
    $integration->mock('get_contact_id_for_email_address', sub {
        $get_contact_email = $_[1];
        return undef;
    });
    my $get_contact_phone;
    $integration->mock('get_contact_id_for_phone_number', sub {
        $get_contact_phone = $_[1];
        return undef;
    });

    my $create_contact_email;
    my $create_contact_first_name;
    my $create_contact_last_name;
    my $create_contact_number;
    $integration->mock('create_contact_and_get_id', sub {
        $create_contact_email = $_[1];
        $create_contact_first_name = $_[2];
        $create_contact_last_name = $_[3];
        $create_contact_number = $_[4];
        return "contact-id";
    });

    my $create_case_payload;
    $integration->mock('create_case_and_get_number', sub {
        $create_case_payload = $_[1];
        return "case-number";
    });

    my $attachment_upload_filename;
    $integration->mock('upload_attachment_from_file_and_get_id', sub {
        $attachment_upload_filename = $_[1];
        return 'attachment-id';
    });

    my $photo_upload = Web::Dispatch::Upload->new(
        tempname => path(__FILE__)->dirname . '/files/test_image.jpg',
        filename => 'image.jpg',
    );
    my $req = POST '/requests.json',
        Content_Type => 'form-data',
        Content => [
            api_key => 'api_key',
            service_code => 'potholes',
            address_string => 'address string',
            email => 'test@example.com',
            first_name => 'first',
            last_name => 'last',
            phone => '07700 900000',
            description => "description",
            uploads => [ $photo_upload ],
            'attribute[title]' => 'title',
            'attribute[description]' => 'description',
            'attribute[easting]' => 100,
            'attribute[northing]' => 101,
            'attribute[fixmystreet_id]' => 10,
            'attribute[NSGRef]' => 'USRN',
            'attribute[UnitID]' => 'asset-id',
            'attribute[report_url]' => 'url',
        ];
    my $res = $endpoint->run_test_request($req);
    ok $res->is_success, 'valid request' or diag $res->content;
    is_deeply decode_json($res->content), [
        {
            service_request_id => 'case-number',
        },
    ];

    is $get_contact_email, 'test@example.com';
    is $get_contact_phone, '07700 900000';

    is $create_contact_email, 'test@example.com';
    is $create_contact_first_name, 'first';
    is $create_contact_last_name, 'last';
    is $create_contact_number, '07700 900000';

    is $attachment_upload_filename, 'test_image.jpg';

    is_deeply $create_case_payload,
        {
            description => "title\n\ndescription\n\nLocation query entered: address string\n\nView report on FixMyStreet: url",
            externalReference => 'FMS10',
            usrn => 'USRN',
            contactId => 'contact-id',
            attachments => [{
                id => 'attachment-id',
            }],
            internalAssetId => 'asset-id',
            caseTypeCode => 'P001',
            easting => '100',
            northing => '101',
            assetTypeCode => 'A001'
        };

    $integration->unmock('get_contact_id_for_email_address');
    $integration->unmock('create_contact_and_get_id');
    $integration->unmock('upload_attachment_from_file_and_get_id');
    $integration->unmock('create_case_and_get_number');
};

subtest "post_service_request_update" => sub {
    my $attachment_upload_filename;
    $integration->mock('upload_attachment_from_file_and_get_id', sub {
        $attachment_upload_filename = $_[1];
        return 'attachment-id';
    });

    my $add_note_case_id;
    my $add_note_payload;
    $integration->mock('add_note_to_case', sub {
        $add_note_case_id = $_[1];
        $add_note_payload = $_[2];
    });

    my $photo_upload = Web::Dispatch::Upload->new(
        tempname => path(__FILE__)->dirname . '/files/test_image.jpg',
        filename => 'image.jpg',
    );
    my $req = POST '/servicerequestupdates.json',
        Content_Type => 'form-data',
        Content => [
            service_request_id => 'case-number',
            api_key => 'api_key',
            description => "description",
            uploads => [ $photo_upload ],
            status => 'CLOSED',
            update_id => 'update_id',
            updated_datetime => '2025-11-05T23:00:00+00:00',
        ];
    my $res = $endpoint->run_test_request($req);
    ok $res->is_success, 'valid request' or diag $res->content;
    is_deeply decode_json($res->content), [
        {
            update_id => 'update_id',
        },
    ];

    is $attachment_upload_filename, 'test_image.jpg';

    is $add_note_case_id, 'case-number';
    is_deeply $add_note_payload,
        {
            noteText => "description",
            attachments => [{
                id => 'attachment-id',
            }],
        };

    $integration->unmock('upload_attachment_from_file_and_get_id');
    $integration->unmock('add_note_to_case');
};

subtest "Filter get updates by date" => sub {
    my $mock_ua = Test::MockModule->new('LWP::UserAgent');
    $mock_ua->mock('request', sub {
        my $uri = "" . $_[1]->uri;  # Concatting with empty string to force string context.
        if ($uri =~ /restype/) {
            return HTTP::Response->new(200, 'OK', [], $updates_list);
        } else {
            return HTTP::Response->new(200, 'OK', [], $update_file);
        }
    });
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.json?start_date=2025-12-02T08:41:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is @{decode_json($res->content)}, 3, 'Filtered to updates after start date';

    $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.json?end_date=2025-12-02T09:45:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is @{decode_json($res->content)}, 2, 'Filtered to updates before end date';

    $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.json?start_date=2025-12-02T09:39:00Z&end_date=2025-12-02T09:41:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is @{decode_json($res->content)}, 1, 'Filtered to updates between start and end date';
};

subtest "Get updates mapping" => sub {
    my $mock_ua = Test::MockModule->new('LWP::UserAgent');
    $mock_ua->mock('request', sub {
        my $uri = "" . $_[1]->uri;  # Concatting with empty string to force string context.
        if ($uri =~ /restype/) {
            return HTTP::Response->new(200, 'OK', [], $updates_list);
        } else {
            return HTTP::Response->new(200, 'OK', [], _edit_update_file($uri));
        }
    });

    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml',
    );

    is $res->content, '<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <description></description>
    <external_status_code>DR020</external_status_code>
    <media_url></media_url>
    <service_request_id>FMS-01</service_request_id>
    <status>in_progress</status>
    <update_id>FMS-01_14</update_id>
    <updated_datetime>2025-12-02T09:46:55Z</updated_datetime>
  </request_update>
  <request_update>
    <description>Ignored unless CS_CLEAR_CASE</description>
    <external_status_code>GN100</external_status_code>
    <media_url></media_url>
    <service_request_id>FMS-03</service_request_id>
    <status>closed</status>
    <update_id>FMS-03_12</update_id>
    <updated_datetime>2025-12-02T09:40:26Z</updated_datetime>
  </request_update>
  <request_update>
    <description></description>
    <external_status_code>GN090</external_status_code>
    <media_url></media_url>
    <service_request_id>FMS-02</service_request_id>
    <status>internal_referral</status>
    <update_id>FMS-02_13</update_id>
    <updated_datetime>2025-12-02T09:40:28Z</updated_datetime>
  </request_update>
  <request_update>
    <description></description>
    <external_status_code>RANDOM</external_status_code>
    <media_url></media_url>
    <service_request_id>FMS-04</service_request_id>
    <status>investigating</status>
    <update_id>FMS-04_11</update_id>
    <updated_datetime>2025-12-02T09:40:00Z</updated_datetime>
  </request_update>
</service_request_updates>
';
};

sub _edit_update_file {
    my $url = shift;

    my $file = decode_json($update_file);
    if ($url =~ /CS_CHANGE_QUEUE/) {
        $file->{Message}->{CaseNumber} = 'FMS-02';
        $file->{Message}->{CaseTypeCode} = 'GN090';
        splice(@{$file->{Message}->{CaseEventHistory}}, -1);
    } elsif ($url =~ /CS_CLEAR_CASE/) {
        $file->{Message}->{CaseNumber} = 'FMS-03';
        $file->{Message}->{CaseTypeCode} = 'GN100';
        splice(@{$file->{Message}->{CaseEventHistory}}, -2);
    } elsif ($url =~ /CS_INSPECTION_PROMPTED/) {
        $file->{Message}->{CaseNumber} = 'FMS-04';
        $file->{Message}->{CaseTypeCode} = 'RANDOM';
        splice(@{$file->{Message}->{CaseEventHistory}}, -3);
    };

    return encode_json($file);
}

done_testing;
