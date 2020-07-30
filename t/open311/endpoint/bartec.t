use strict; use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::MockTime ':all';
use Test::Warn;
use Test::Output;
use JSON::MaybeXS;
use Path::Tiny;
use SOAP::Lite;
use SOAP::Transport::HTTP;
use HTTP::Request::Common;

BEGIN { $ENV{TEST_MODE} = 1; }

use Open311::Endpoint::Integration::Bartec;
my $endpoint = Open311::Endpoint::Integration::Bartec->new( jurisdiction_id => 'bartec' );

my $integration = Test::MockModule->new('Integrations::Bartec');
$integration->mock('_build_config_file', sub {
    path(__FILE__)->sibling('bartec.yml');
});

sub ServiceRequests_Updates_Get {
    my %args = @_;

    my ($date) = $args{envelope} =~ /<LastUpdated [^>]*>([^>]*)</;
    $date =~ s/(\d+)-(\d+)-(\d+)T.*/$1$2$3/;
    my $path = "xml/bartec/servicerequests_updates_get_$date.xml";

    return path(__FILE__)->parent(1)->realpath->child($path)->slurp;
}

sub ServiceRequests_Get {
    my %args = @_;

    my ($id) = $args{envelope} =~ /<ServiceCode[^>]*>([^>]*)</;
    my $path = "xml/bartec/servicerequests_get_$id.xml";

    return path(__FILE__)->parent(1)->realpath->child($path)->slurp,
}

sub ServiceRequests_Create {
    my %args = @_;

    my $path = 'xml/bartec/servicerequests_create.xml';

    my ($id) = $args{envelope} =~ /<External[^>]*>([^>]*)</;
    if ( $id eq '200' ) {
        $path = "xml/bartec/servicerequests_create_error.xml";
    }

    return path(__FILE__)->parent(1)->realpath->child($path)->slurp,
}

sub ServiceRequests_Notes_Create {
    my %args = @_;

    if ( $args{envelope} =~ /failing note/s ) {
        return '<ServiceRequests_Notes_CreateResponse><ServiceRequests_Notes_CreateResult><Errors><Message>FAIL!</Message></Errors></ServiceRequests_Notes_CreateResult></ServiceRequests_Notes_CreateResponse>';
    }

    return '<ServiceRequests_Notes_CreateResult />';
}

sub Service_Request_Document_Create {
    my %args = @_;

    if ( $args{envelope} =~ /5001/s ) {
        return '<Service_Request_Document_CreateResponse><Service_Request_Document_CreateResult><Errors><Message>FAIL!</Message></Errors></Service_Request_Document_CreateResult></Service_Request_Document_CreateResponse>';
    }

    return '<Service_Request_Document_CreateResult />';
}

sub ServiceRequests_History_Get {
    my %args = @_;

    my ($id) = $args{envelope} =~ /<ServiceRequestID[^>]*>([^>]*)</;
    my $path = "xml/bartec/servicerequests_history_get_$id.xml";
    return path(__FILE__)->parent(1)->realpath->child($path)->slurp;
}

my %responses = (
    Authenticate => '<AuthenticateResponse xmlns="http://bartec-systems.com/">
  <AuthenticateResult xmlns="http://www.bartec-systems.com">
    <Token><TokenString>ABC=</TokenString></Token>
    <Errors />
  </AuthenticateResult>
</AuthenticateResponse>',
    ServiceRequests_Types_Get => path(__FILE__)->parent(1)->realpath->child('xml/bartec/servicerequests_types_get.xml')->slurp,
    ServiceRequests_Create => \&ServiceRequests_Create,
    ServiceRequests_Statuses_Get => path(__FILE__)->parent(1)->realpath->child('xml/bartec/servicerequests_status_get.xml')->slurp,
    Premises_Get => path(__FILE__)->parent(1)->realpath->child('xml/bartec/get_premises.xml')->slurp,
    ServiceRequests_History_Get =>  \&ServiceRequests_History_Get,
    ServiceRequests_Updates_Get =>  \&ServiceRequests_Updates_Get,
    ServiceRequests_Get => \&ServiceRequests_Get,
    Service_Request_Document_Create => \&Service_Request_Document_Create,
    ServiceRequests_Notes_Types_Get => path(__FILE__)->parent(1)->realpath->child('xml/bartec/servicerequests_notes_types_get.xml')->slurp,
    ServiceRequests_Notes_Create => \&ServiceRequests_Notes_Create,
);

sub gen_full_response {
    my ($append) = @_;

    my $xml .= <<EOF;
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
               xmlns:xsd="http://www.w3.org/2001/XMLSchema">
<soap:Body>$append</soap:Body>
</soap:Envelope>
EOF

    return $xml;
}

my %sent;

my $t = SOAP::Transport::HTTP::Client->new();
my $transport = Test::MockModule->new('SOAP::Transport::HTTP::Client', no_auto => 1);
$transport->mock(send_receive => sub {
        my $self = shift;
        my %args = @_;


        (my $action = $args{action}) =~ s#http://bartec-systems.com/##;
        $action =~ s/"//g;
        $sent{$action} = $args{envelope};

        my $resp = $responses{$action};
        if ( ref $resp eq 'CODE' ) {
            $resp = $resp->(%args);
        }
        return gen_full_response( $resp );
    }
);

my $i = Test::MockModule->new('Open311::Endpoint::Integration::Bartec');
$i->mock('_get_photos', sub {
        my $h = HTTP::Headers->new;
        $h->header( 'Content-Disposition' => 'attachment; filename="1.1.jpg"' );
        return [ HTTP::Response->new( 200, 'OK', $h, 'content' ) ];
    }
);

subtest "check fetch service description" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services.json?jurisdiction_id=bartec',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [
    {
        service_code => "1",
        service_name => "Leaf removal",
        description => "Leaf removal",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Street cleansing" ]
    },
    {
        service_code => "3",
        service_name => "Rubbish (Street cleansing)",
        description => "Rubbish",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Street cleansing" ]
    },
    {
        service_code => "4",
        service_name => "Rubbish (Parks)",
        description => "Rubbish",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Parks" ]
    },
    {
        service_code => "5",
        service_name => "Offensive graffiti",
        description => "Offensive graffiti",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Graffiti" ]
    },
    ],
    'correct services returned';
};

subtest "check fetch service" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services/1.json?jurisdiction_id=bartec',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    {
        service_code => "1",
        attributes => [
          {
            variable => 'false',
            code => "easting",
            datatype => "number",
            required => 'true',
            datatype_description => '',
            order => 1,
            description => "easting",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "northing",
            datatype => "number",
            required => 'true',
            datatype_description => '',
            order => 2,
            description => "northing",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "fixmystreet_id",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 3,
            description => "external system ID",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "report_url",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 4,
            description => "Report URL",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "title",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 5,
            description => "Title",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "description",
            datatype => "text",
            required => 'true',
            datatype_description => '',
            order => 6,
            description => "Description",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "asset_details",
            datatype => "text",
            required => 'false',
            datatype_description => '',
            order => 7,
            description => "Asset information",
            automated => 'hidden_field',
          },
          {
            variable => 'true',
            code => "site_code",
            datatype => "text",
            required => 'false',
            datatype_description => '',
            order => 8,
            description => "Site code",
            automated => 'hidden_field',
          },
          {
            variable => 'true',
            code => "central_asset_id",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 9,
            description => "Central Asset ID",
            automated => 'hidden_field',
          },
          {
            variable => 'true',
            code => "closest_address",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 10,
            description => "Closest address",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "postcode",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 11,
            description => "postcode",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "street",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 12,
            description => "Closest street",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "house_no",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 13,
            description => "Closest house number",
            automated => 'server_set',
          },
        ]
    },
    'correct services returned';
};

subtest "check send failed report sending" => sub {
    set_fixed_time('2020-06-17T16:28:30Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'bartec',
        api_key => 'test',
        service_code => '1',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '52.540930',
        long => '-0.289832',
        'attribute[fixmystreet_id]' => 200,
        'attribute[northing]' => 1,
        'attribute[easting]' => 1,
        'attribute[description]' => 'a description',
        'attribute[report_url]' => 1,
        'attribute[title]' => 'a title',
        'attribute[house_no]' => '14',
        'attribute[street]' => 'a street',
        'attribute[postcode]' => 'AB1 1BA',
        'attribute[closest_address]' => "Nearest road to the pin placed on the map (automatically generated by Bing Maps): 22 A Street, A Town. XX1 1ZZ\nNearest postcode (automatically generate): XX1 1ZZ",
    );

    is $res->code, 500, 'request is an error';
    like $res->content, qr/Specified UPRN does not exist/, 'error message output';
};

subtest "check send basic report" => sub {
    set_fixed_time('2020-06-17T16:28:30Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'bartec',
        api_key => 'test',
        service_code => '1',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '52.540930',
        long => '-0.289832',
        'attribute[fixmystreet_id]' => 1,
        'attribute[northing]' => 1,
        'attribute[easting]' => 1,
        'attribute[description]' => 'a description',
        'attribute[report_url]' => 1,
        'attribute[title]' => 'a title',
        'attribute[house_no]' => '14',
        'attribute[street]' => 'a street',
        'attribute[postcode]' => 'AB1 1BA',
        'attribute[closest_address]' => "Nearest road to the pin placed on the map (automatically generated by Bing Maps): 22 A Street, A Town. XX1 1ZZ\nNearest postcode (automatically generate): XX1 1ZZ",
    );

    is $sent{Service_Request_Document_Create}, undef, "skip document create if no photo";

    my $sr_sent = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Get} );
    is_deeply $sr_sent->body->{ServiceRequests_Get}, {
        token => 'ABC=',
        ServiceCode => '0001',
    }, "correct request for servicerequests_get";

    my $create_req = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Create} );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply $create_req->body->{ServiceRequests_Create}, {
        DateRequested => '2020-06-17T17:28:30+01:00',
        token => 'ABC=',
        UPRN => 987654321,
        ServiceTypeID => 1,
        ServiceStatusID => 2276,
        CrewID => 11,
        LandTypeID => 12,
        SLAID => 13,
        serviceLocationDescription => "22 A Street, A Town. XX1 1ZZ",
        ServiceRequest_Location => {
            Metric => {
                Longitude => -0.289832,
                Latitude => 52.540930,
            }
        },
        #source => 'FixMyStreet',
        ExternalReference => 1,
        reporterContact => {
            Forename => 'Bob',
            Surname => 'Mould',
            Email => 'test@example.com',
            ReporterType => 'Public',
        }
    }, 'correct request sent';

    my $note_sent = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Notes_Create} );
    is_deeply $note_sent->body->{ServiceRequests_Notes_Create}, {
        token => 'ABC=',
        ServiceRequestID => '0001',
        NoteTypeID => 11,
        Note => "a title\n\na description",
        Comment => 'Note added by FixMyStreet',
    }, 'correct note created';

    is_deeply decode_json($res->content), [ { service_request_id => '0001' } ], 'correct return';
};

subtest "check failed to attach note" => sub {
    set_fixed_time('2020-06-17T16:28:30Z');
    my $res;
    warnings_like {
        $res = $endpoint->run_test_request(
            POST => '/requests.json',
            jurisdiction_id => 'bartec',
            api_key => 'test',
            service_code => '1',
            first_name => 'Bob',
            last_name => 'Mould',
            email => 'test@example.com',
            description => 'a failing note',
            lat => '52.540930',
            long => '-0.289832',
            'attribute[fixmystreet_id]' => 1,
            'attribute[northing]' => 1,
            'attribute[easting]' => 1,
            'attribute[description]' => 'a failing note',
            'attribute[report_url]' => 1,
            'attribute[title]' => 'a title',
            'attribute[house_no]' => '14',
            'attribute[street]' => 'a street',
            'attribute[postcode]' => 'AB1 1BA',
            'attribute[closest_address]' => "Nearest road to the pin placed on the map (automatically generated by Bing Maps): 22 A Street, A Town. XX1 1ZZ\nNearest postcode (automatically generate): XX1 1ZZ",
        );
    } qr/failed to attach note/, 'warning issued if note did not attach';

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), [ { service_request_id => '0001' } ], 'correct return';
};

subtest "check send report with assets" => sub {
    set_fixed_time('2020-06-17T16:28:30Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'bartec',
        api_key => 'test',
        service_code => '1',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '52.540930',
        long => '-0.289832',
        'attribute[fixmystreet_id]' => 1,
        'attribute[northing]' => 1,
        'attribute[easting]' => 1,
        'attribute[description]' => 'a description',
        'attribute[report_url]' => 1,
        'attribute[central_asset_id]' => '8080',
        'attribute[asset_details]' => 'this is an asset',
        'attribute[title]' => 'a title',
        'attribute[house_no]' => '14',
        'attribute[street]' => 'a street',
        'attribute[postcode]' => 'AB1 1BA',
        'attribute[closest_address]' => 'Nearest road to the pin placed on the map (automatically generated by Bing Maps): 22 A Street, A Town. XX1 1ZZ',
    );

    is $sent{Service_Request_Document_Create}, undef, "skip document create if no photo";

    my $sr_sent = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Get} );
    is_deeply $sr_sent->body->{ServiceRequests_Get}, {
        token => 'ABC=',
        ServiceCode => '0001',
    }, "correct request for servicerequests_get";

    my $create_req = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Create} );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply $create_req->body->{ServiceRequests_Create}, {
        DateRequested => '2020-06-17T17:28:30+01:00',
        token => 'ABC=',
        UPRN => 987654321,
        ServiceTypeID => 1,
        ServiceStatusID => 2276,
        CrewID => 11,
        LandTypeID => 12,
        SLAID => 13,
        serviceLocationDescription => "22 A Street, A Town. XX1 1ZZ",
        ServiceRequest_Location => {
            Metric => {
                Longitude => -0.289832,
                Latitude => 52.540930,
            }
        },
        #source => 'FixMyStreet',
        ExternalReference => 1,
        reporterContact => {
            Forename => 'Bob',
            Surname => 'Mould',
            Email => 'test@example.com',
            ReporterType => 'Public',
        }
    }, 'correct request sent';

    my $note_sent = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Notes_Create} );
    is_deeply $note_sent->body->{ServiceRequests_Notes_Create}, {
        token => 'ABC=',
        ServiceRequestID => '0001',
        NoteTypeID => 11,
        Note => "a title\n\na description\n\nAsset id: 8080\nAsset detail: this is an asset",
        Comment => 'Note added by FixMyStreet',
    }, 'correct note created';

    is_deeply decode_json($res->content), [ { service_request_id => '0001' } ], 'correct return';
};


subtest "check send report with a photo" => sub {
    set_fixed_time('2020-06-17T16:28:30Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'bartec',
        api_key => 'test',
        service_code => '1',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '52.540930',
        long => '-0.289832',
        'attribute[fixmystreet_id]' => 1,
        'attribute[northing]' => 1,
        'attribute[easting]' => 1,
        'attribute[description]' => 'a description',
        'attribute[report_url]' => 1,
        'attribute[title]' => 'a title',
        'attribute[house_no]' => '14',
        'attribute[street]' => 'a street',
        'attribute[postcode]' => 'AB1 1BA',
        'attribute[closest_address]' => '22 A Street, A Town. XX1 1ZZ',
        media_url => 'http://example.com/1.1.jpg',
    );

    my $create_req = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Create} );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply $create_req->body->{ServiceRequests_Create}, {
        DateRequested => '2020-06-17T17:28:30+01:00',
        token => 'ABC=',
        UPRN => 987654321,
        ServiceTypeID => 1,
        ServiceStatusID => 2276,
        CrewID => 11,
        LandTypeID => 12,
        SLAID => 13,
        serviceLocationDescription => "22 A Street, A Town. XX1 1ZZ",
        ServiceRequest_Location => {
            Metric => {
                Longitude => -0.289832,
                Latitude => 52.540930,
            }
        },
        #source => 'FixMyStreet',
        ExternalReference => 1,
        reporterContact => {
            Forename => 'Bob',
            Surname => 'Mould',
            Email => 'test@example.com',
            ReporterType => 'Public',
        }
    }, 'correct request sent';

    my $sr_sent = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Get} );
    is_deeply $sr_sent->body->{ServiceRequests_Get}, {
        token => 'ABC=',
        ServiceCode => '0001',
    }, "correct request for servicerequests_get";

    my $sr_doc = SOAP::Deserializer->deserialize( $sent{Service_Request_Document_Create} );
    is_deeply $sr_doc->body->{Service_Request_Document_Create}, {
        token => 'ABC=',
        Public => 'true',
        ServiceRequestID => '0001',
        DateTaken => '2020-06-17T17:28:30+01:00',
        Comment => 'Photo uploaded from FixMyStreet',
        AttachedDocument => {
            FileExtension => 'jpg',
            ID => '11',
            Name => '1.1.jpg',
            Document => 'Y29udGVudA==',
        }
    }, "correct request to create photo";

    is_deeply decode_json($res->content), [ { service_request_id => '0001' } ], 'correct return';
};

subtest "check failing to attach a photo" => sub {
    set_fixed_time('2020-06-17T16:28:30Z');
    my $res;
    warnings_like {
        $res = $endpoint->run_test_request(
            POST => '/requests.json',
            jurisdiction_id => 'bartec',
            api_key => 'test',
            service_code => '1',
            first_name => 'Bob',
            last_name => 'Mould',
            email => 'test@example.com',
            description => 'description',
            lat => '52.540930',
            long => '-0.289832',
            'attribute[fixmystreet_id]' => 500,
            'attribute[northing]' => 1,
            'attribute[easting]' => 1,
            'attribute[description]' => 'a description',
            'attribute[report_url]' => 1,
            'attribute[title]' => 'a title',
            'attribute[house_no]' => '14',
            'attribute[street]' => 'a street',
            'attribute[postcode]' => 'AB1 1BA',
            'attribute[closest_address]' => '22 A Street, A Town. XX1 1ZZ',
            media_url => 'http://example.com/500.1.jpg',
        );
    } qr/failed to attach photo/, 'warning issued if photo failed to attach';

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), [ { service_request_id => '0001' } ], 'correct return';
};

subtest "check send report with a photo as an upload" => sub {
    set_fixed_time('2020-06-17T16:28:30Z');
    %sent = ();
    my $file = Web::Dispatch::Upload->new(
        headers => '',
        tempname => path(__FILE__)->dirname . '/files/bartec/image.jpg',
        filename => 'image.jpg',
        size => 10,
    );

    my $req = POST '/requests.json',
        Content_Type => 'form-data',
        Content => [
            jurisdiction_id => 'bartec',
            api_key => 'test',
            service_code => '1',
            first_name => 'Bob',
            last_name => 'Mould',
            email => 'test@example.com',
            description => 'description',
            lat => '52.540930',
            long => '-0.289832',
            'attribute[fixmystreet_id]' => 1,
            'attribute[northing]' => 1,
            'attribute[easting]' => 1,
            'attribute[description]' => 'a description',
            'attribute[report_url]' => 1,
            'attribute[title]' => 'a title',
            'attribute[house_no]' => '14',
            'attribute[street]' => 'a street',
            'attribute[postcode]' => 'AB1 1BA',
            'attribute[closest_address]' => '22 A Street, A Town. XX1 1ZZ',
            uploads => [ $file ],
        ];
    my $res = $endpoint->run_test_request($req);

    my $create_req = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Create} );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply $create_req->body->{ServiceRequests_Create}, {
        DateRequested => '2020-06-17T17:28:30+01:00',
        token => 'ABC=',
        UPRN => 987654321,
        ServiceTypeID => 1,
        ServiceStatusID => 2276,
        CrewID => 11,
        LandTypeID => 12,
        SLAID => 13,
        serviceLocationDescription => "22 A Street, A Town. XX1 1ZZ",
        ServiceRequest_Location => {
            Metric => {
                Longitude => -0.289832,
                Latitude => 52.540930,
            }
        },
        #source => 'FixMyStreet',
        ExternalReference => 1,
        reporterContact => {
            Forename => 'Bob',
            Surname => 'Mould',
            Email => 'test@example.com',
            ReporterType => 'Public',
        }
    }, 'correct request sent';

    my $sr_sent = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Get} );
    is_deeply $sr_sent->body->{ServiceRequests_Get}, {
        token => 'ABC=',
        ServiceCode => '0001',
    }, "correct request for servicerequests_get";

    my $sr_doc = SOAP::Deserializer->deserialize( $sent{Service_Request_Document_Create} );
    is_deeply $sr_doc->body->{Service_Request_Document_Create}, {
        token => 'ABC=',
        Public => 'true',
        ServiceRequestID => '0001',
        DateTaken => '2020-06-17T17:28:30+01:00',
        Comment => 'Photo uploaded from FixMyStreet',
        AttachedDocument => {
            FileExtension => 'jpg',
            ID => '11',
            Name => 'image.jpg',
            Document => 'VGhpcyBpcyBhIGZha2UgaW1hZ2UK',
        }
    }, "correct request to create photo";

    is_deeply decode_json($res->content), [ { service_request_id => '0001' } ], 'correct return';
};

subtest 'get address from bounding box' => sub {
    my $uprn = $endpoint->get_nearest_uprn({
            long => -0.28938,
            lat => 52.540936,
            service_code => 1,
            attributes => {
                site_code => 123456789
            },
    });

    my $get_prem_obj = SOAP::Deserializer->deserialize( $sent{Premises_Get} );
    my $point1 = $get_prem_obj->dataof('//Point1/Metric');
    my $point2 = $get_prem_obj->dataof('//Point2/Metric');

    is $point1->attr->{Latitude}, 52.541374, "point 1 longitude correct";
    is $point1->attr->{Longitude}, -0.290116, "point 1 latitude correct";
    is $point2->attr->{Latitude}, 52.540498, "point 2 longitude correct";
    is $point2->attr->{Longitude}, -0.288644, "point 2 latitude correct";

    my $get_prem_req = $get_prem_obj->body->{Premises_Get};

    is_deeply $get_prem_req, {
        token => 'ABC=',
        UPRN => undef,
        Bounds => {
            Point1 => { Metric => '' },
            Point2 => { Metric => '' },
        }
    }, "sent bounding box";

    is $uprn, 100000101, "got correct uprn";
};

subtest 'get open space address from bounding box' => sub {
    my $uprn = $endpoint->get_nearest_uprn({
            long => -0.28938,
            lat => 52.540936,
            service_code => 100,
            attributes => {
                site_code => 123456789
            },
    });

    is $uprn, 987654323 , "got correct uprn";
};

subtest 'get uprn for usrn' => sub {
    my $uprn = $endpoint->get_nearest_uprn({
            long => -0.28938,
            lat => 52.540936,
            service_code => 200,
            attributes => {
                site_code => 123456789
            },
    });

    my $get_prem_obj = SOAP::Deserializer->deserialize( $sent{Premises_Get} );
    my $get_prem_req = $get_prem_obj->body->{Premises_Get};

    is_deeply $get_prem_req, {
        token => 'ABC=',
        UPRN => undef,
        USRN => 123456789,
    }, "only used USRN in request";

    is $uprn,987654321 , "got correct uprn";
};

subtest 'fetch updates' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.json?jurisdiction_id=bartec&start_date=2020-06-19T10:00:00Z&end_date=2020-06-19T12:00:00Z'
    );

    my $sent_updates = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Updates_Get} );
    my $sent_history = SOAP::Deserializer->deserialize( $sent{ServiceRequests_History_Get} );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply $sent_updates->body->{ServiceRequests_Updates_Get}, {
        token => 'ABC=',
        LastUpdated => '2020-06-19T10:00:00Z',
    }, 'correct fetch updates request sent';

    is_deeply $sent_history->body->{ServiceRequests_History_Get}, {
        token => 'ABC=',
        ServiceRequestID => '51340',
        Date => '2020-06-19T10:00:00Z',
    }, 'correct fetch history request sent';

    is_deeply decode_json($res->content), [
        {
            update_id =>228025,
            service_request_id =>'SR00051627',
            status =>'open',
            updated_datetime => '2020-06-17T09:47:26+01:00',
            description =>'',
            media_url =>'',
        },
        {
            update_id =>228026,
            service_request_id =>'SR00051628',
            status =>'fixed',
            updated_datetime => '2020-06-17T09:48:26+01:00',
            description =>'',
            media_url =>'',
        },
        {
            update_id =>228027,
            service_request_id =>'SR00051627',
            status =>'open',
            updated_datetime => '2020-06-17T09:55:36+01:00',
            description =>'',
            media_url =>'',
        },
        {
            update_id =>228028,
            service_request_id =>'SR00051624',
            status =>'closed',
            updated_datetime => '2020-06-17T09:59:26+01:00',
            description =>'',
            media_url =>'',
        }
    ], 'correct return';
};

subtest 'fetch_requests' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/requests.json?jurisdiction_id=bartec&start_date=2020-06-20T10:00:00Z&end_date=2020-06-20T12:00:00Z'
    );

    my $sent_updates = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Updates_Get} );
    my $sent_get = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Get} );

    is_deeply $sent_updates->body->{ServiceRequests_Updates_Get}, {
        token => 'ABC=',
        LastUpdated => '2020-06-20T10:00:00Z',
    }, 'correct fetch updates request sent';

    is_deeply $sent_get->body->{ServiceRequests_Get}, {
        token => 'ABC=',
        ServiceCode => 'SR4',
    }, 'correct fetch history request sent';

    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply decode_json($res->content), [
        {
            lat => "52.543786",
            long => "-0.567652",
            address_id => "",
            service_request_id => "SR2",
            address => "",
            requested_datetime => "2020-06-23T16:17:00+01:00",
            updated_datetime => "2020-06-23T16:17:00+01:00",
            media_url => "",
            status => "open",
            service_name => "Leaf removal",
            zipcode => "",
            service_code => "271"
        }
    ], 'correct list of requests';
};

subtest 'fetch_requests with mapped service' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/requests.json?jurisdiction_id=bartec&start_date=2020-06-22T10:00:00Z&end_date=2022-06-20T12:00:00Z'
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply decode_json($res->content), [
        {
            lat => "52.543786",
            long => "-0.567652",
            address_id => "",
            service_request_id => "SR5",
            address => "",
            requested_datetime => "2020-06-24T16:17:00+01:00",
            updated_datetime => "2020-06-24T16:17:00+01:00",
            media_url => "",
            status => "open",
            service_name => "Offensive graffiti",
            zipcode => "",
            service_code => "281"
        }
    ], 'correct list of requests';
};

subtest 'fetch_requests with no results' => sub {
    %sent = ();

    my $res = $endpoint->run_test_request(
        GET => '/requests.json?jurisdiction_id=bartec&start_date=2020-06-21T10:00:00Z&end_date=2020-06-21T12:00:00Z'
    );

    my $sent_updates = SOAP::Deserializer->deserialize( $sent{ServiceRequests_Updates_Get} );
    my $sent_get = $sent{ServiceRequests_Get};

    is $sent_get, undef, 'no attempt to get a request';

    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply decode_json($res->content), [ ], 'empty list of requests';
};

done_testing;
