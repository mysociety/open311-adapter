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
use JSON::MaybeXS;
use Path::Tiny;
use Test::MockModule;
use Test::More;
use Test::LongString;
use Web::Dispatch::Upload;

my $integration = Test::MockModule->new("Integrations::Aurora");
my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

BEGIN { $ENV{TEST_MODE} = 1; }

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

subtest "get_service_request_updates" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.json',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
};

done_testing;
