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

    $integration->mock('upload_attachment_from_file_and_get_id', sub {
        is length(path($_[1])->slurp), 160, 'correct file size';
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

    is_deeply $create_case_payload,
        {
            description => "title\n\ndescription\n\nLocation query entered: address string\n\nView report on FixMyStreet: url",
            externalReference => 'FMS10',
            usrn => 'USRN',
            contactId => 'contact-id',
            attachments => [{
                id => 'attachment-id',
                name => 'test_image.jpg',
            }],
            internalAssetId => 'asset-id',
            caseTypeCode => 'P001',
            easting => '100',
            northing => '101',
            assetTypeCode => 'A001',
            locationText => 'title'
        };

    $integration->unmock('get_contact_id_for_email_address');
    $integration->unmock('create_contact_and_get_id');
    $integration->unmock('upload_attachment_from_file_and_get_id');
    $integration->unmock('create_case_and_get_number');
};

subtest "post_service_request_update" => sub {
    $integration->mock('upload_attachment_from_file_and_get_id', sub {
        is length(path($_[1])->slurp), 160, 'correct file size';
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

    is $add_note_case_id, 'case-number';
    is_deeply $add_note_payload,
        {
            noteText => "description",
            attachments => [{
                id => 'attachment-id',
                name => 'test_image.jpg',
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
    is @{decode_json($res->content)}, 4, 'Filtered to updates after start date';

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
    <external_status_code>DR02</external_status_code>
    <media_url></media_url>
    <service_request_id>FMS-01</service_request_id>
    <status>in_progress</status>
    <update_id>FMS-01_14</update_id>
    <updated_datetime>2025-12-02T09:46:55Z</updated_datetime>
  </request_update>
  <request_update>
    <description>Ignored unless CS_CLEAR_CASE
(Also newlines unescaped)</description>
    <external_status_code>GN10</external_status_code>
    <media_url></media_url>
    <service_request_id>FMS-03</service_request_id>
    <status>closed</status>
    <update_id>FMS-03_12</update_id>
    <updated_datetime>2025-12-02T09:40:26Z</updated_datetime>
  </request_update>
  <request_update>
    <description></description>
    <external_status_code>CS_CHANGE_QUEUE</external_status_code>
    <media_url></media_url>
    <service_request_id>FMS-02</service_request_id>
    <status>unchanged</status>
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
  <request_update>
    <description></description>
    <external_status_code>CS_MAINTENANCE_COMPLETED</external_status_code>
    <media_url></media_url>
    <service_request_id>FMS-05</service_request_id>
    <status>fixed</status>
    <update_id>FMS-05_10</update_id>
    <updated_datetime>2025-12-02T09:39:54Z</updated_datetime>
  </request_update>
</service_request_updates>
';
};

sub _edit_update_file {
    my $url = shift;

    my $file = decode_json($update_file);
    if ($url =~ /CS_CHANGE_QUEUE/) {
        $file->{Message}->{CaseNumber} = 'FMS-02';
        $file->{Message}->{ClearanceReasonCode} = '';
        splice(@{$file->{Message}->{CaseEventHistory}}, -1);
    } elsif ($url =~ /CS_CLEAR_CASE/) {
        $file->{Message}->{CaseNumber} = 'FMS-03';
        $file->{Message}->{ClearanceReasonCode} = 'GN10';
        splice(@{$file->{Message}->{CaseEventHistory}}, -2);
    } elsif ($url =~ /CS_INSPECTION_PROMPTED/) {
        $file->{Message}->{CaseNumber} = 'FMS-04';
        $file->{Message}->{ClearanceReasonCode} = 'RANDOM';
        splice(@{$file->{Message}->{CaseEventHistory}}, -3);
    } elsif ($url =~ /CS_MAINTENANCE_COMPLETED/) {
        $file->{Message}->{CaseNumber} = 'FMS-05';
        $file->{Message}->{ClearanceReasonCode} = '';
        splice(@{$file->{Message}->{CaseEventHistory}}, -4);
    };

    return encode_json($file);
}

subtest "Handle update filenames query pagination" => sub {
    my $page1 = <<'XML';
<?xml version="1.0" encoding="utf-8"?>
<EnumerationResults ServiceEndpoint="https://my_api.example.com/" ContainerName="azure-container">
    <Blobs>
        <Blob><Name>20251202_08402699_9664_CS_RE_QUEUE.json</Name></Blob>
        <Blob><Name>20251202_09402699_9664_CS_CLEAR_CASE.json</Name></Blob>
    </Blobs>
    <NextMarker>page-2-token</NextMarker>
</EnumerationResults>
XML
    my $page2 = <<'XML';
<?xml version="1.0" encoding="utf-8"?>
<EnumerationResults ServiceEndpoint="https://my_api.example.com/" ContainerName="azure-container">
    <Blobs>
        <Blob><Name>20251203_09402699_9664_CS_INSPECTION_PROMPTED.json</Name></Blob>
    </Blobs>
    <NextMarker />
</EnumerationResults>
XML

    my @requested_uris;
    my $mock_ua = Test::MockModule->new('LWP::UserAgent');
    $mock_ua->mock('request', sub {
        my $uri =  $_[1]->uri;
        push @requested_uris, $uri;
        my $body = $uri =~ /marker=page-2-token/ ? $page2 : $page1;
        return HTTP::Response->new(200, 'OK', [], $body);
    });

    my @files = $endpoint->aurora->fetch_update_filenames;

    is scalar(@requested_uris), 2, 'Followed NextMarker onto a second page';
    like $requested_uris[1], qr/[?&]marker=page-2-token(?:&|$)/, 'Second request passed the marker';
    is_deeply [ map { $_->{Name} } @files ], [
        '20251202_08402699_9664_CS_RE_QUEUE.json',
        '20251202_09402699_9664_CS_CLEAR_CASE.json',
        '20251203_09402699_9664_CS_INSPECTION_PROMPTED.json',
    ], 'Blobs from every page returned';
};

done_testing;
