package Integrations::WDM;

use Moo;
use Encode qw(encode_utf8);
use XML::Simple;
use SOAP::Lite;
use DateTime::Format::Strptime;

with 'Role::Config';

sub endpoint_url { $_[0]->config->{endpoint_url} }

has xml => (
    is => 'lazy',
    default => sub {
        XML::Simple->new(
            NoAttr => 1,
            KeepRoot => 1,
            SuppressEmpty => 0,
            KeyAttr => [],
        );
    },
);

has 'requests_endpoint' => (
    is => 'ro',
    default => 'requests.xml',
);

has 'updates_endpoint' => (
    is => 'ro',
    default => 'updates.xml',
);

sub format_datetime {
    my ($self, $dt) = @_;

    my $fmt = DateTime::Format::Strptime->new(
        pattern => '%Y-%m-%d %H:%M:%S'
    );

    return $fmt->format_datetime($dt)
}

sub parse_w3c_datetime {
    my ($self, $dt_string) = @_;

    my $w3c = DateTime::Format::W3CDTF->new;
    my $dt = $w3c->parse_datetime($dt_string);

    return $dt;
}

sub post_request {
    my ($self, $service, $args) = @_;

    my $fms_id = $args->{attributes}->{external_id};
    my $name = join(' ', ($args->{first_name}, $args->{last_name}));

    my $tz = DateTime::TimeZone->new( name => 'Europe/London' );
    my $now = DateTime->now( time_zone => $tz );
    my $time = $self->format_datetime($now);

    my @placenames;
    push @placenames, $args->{address_string} if $args->{address_string};
    push @placenames, $args->{postcode} if $args->{postcode};

    my $category_details = $self->_category_mapping($args->{service_code});
    my $data = {
        wdmenquiry => {
            enquiry_time => $time,
            enquiry_reference => '',
            enquiry_source => 'FixMyStreet',
            enquiry_category_code => '',
            enquiry_type_code => '',
            enquiry_detail_code => $args->{service_code},
            usrn => 0, # Ignore provided USRN as WDM doesn't always do the right thing with it
            location=> {
                item_uid => '',
                placename => join(', ', @placenames),
            },
            easting => $args->{attributes}->{easting},
            northing => $args->{attributes}->{northing},
            comments => $args->{description},
            customer_details => {
                name => {
                    firstname => $args->{first_name},
                    lastname => $args->{last_name},
                },
                email => $args->{email} || '',
                telephone_number => $args->{phone} || '',
            },
            external_system_reference => $fms_id,
        }
    };
    if ( defined $args->{media_url} && @{$args->{media_url}} ) {
        $data->{wdmenquiry}->{documents} = {};
        $data->{wdmenquiry}->{documents}->{URL} = $args->{media_url};
    }
    my $response = $self->soap_post($self->requests_endpoint, 'CreateEnquiry', 'xDoc', $self->_create_xml_string($data));


    my $resp_text = $response->valueof('//CreateEnquiryResponse/CreateEnquiryResult') || 'No Enquiry Response';
    if ($resp_text eq 'OK' || $resp_text =~ /Thank you for your feed back/ || $resp_text =~ /External system reference '$fms_id' already exists in database/) {
        # WDM doesn't return a reference in the response to new enquiries so we have
        # to use the FMS ID, which WDM includes when fetching updates.
        return $fms_id;
    } else {
        die $resp_text;
    }
}

sub post_update {
    my ($self, $args) = @_;

    my $time = $self->format_datetime( $self->parse_w3c_datetime( $args->{updated_datetime} ) );

    my $data = {
        wdmupdateenquiry => {
            enquiry_reference => $args->{service_request_id},
            enquiry_time => $time,
            comments => $args->{description},
            customer_details => {
                name => {
                    firstname => $args->{first_name},
                    lastname => $args->{last_name},
                    email => $args->{email},
                    telephone_number => $args->{phone} || '',
                },
            }
        }
    };
    my $response = $self->soap_post($self->updates_endpoint, 'UpdateWdmEnquiry', 'xDoc', $self->_create_xml_string($data));

    my $resp_text = $response->valueof('//UpdateWdmEnquiryResponse/UpdateWdmEnquiryResult');
    if ($resp_text eq 'OK') {
        return {
            status => $args->{status},
            update_id => $args->{update_id},
            update_time => $self->parse_w3c_datetime( $args->{updated_datetime} ),
        };
    } else {
        die $resp_text;
    }
}

sub raise_defect {
    my ($self, $args) = @_;

    my $time = $self->parse_w3c_datetime( $args->{updated_datetime} )->strftime('%d/%m/%Y %H:%M');
    my $defect_mapping = $self->config->{defect_mapping};
    my $attrs = $args->{attributes};
    my $data = {
        wdminstruction => {
            external_system_reference => $args->{service_request_id}, # XXX OR WDM REF?
            usrn => 0, # Ignore provided USRN
            comments => $attrs->{extra_details},
            location_description => $attrs->{defect_location_description} || '',
            item_category_uid => $defect_mapping->{category}{$attrs->{defect_item_category} || ''} || '',
            item_type_uid => $defect_mapping->{type}{$attrs->{defect_item_type} || ''} || '',
            item_detail_uid => $defect_mapping->{detail}{$attrs->{defect_item_detail} || ''} || '',
            easting => $attrs->{easting} || '',
            northing => $attrs->{northing} || '',
            instruction_time => $time,
            response_time_uid => '73', # Hard coded 28 days
        }
    };
    if ( defined $args->{media_url} && @{$args->{media_url}} ) {
        $data->{wdminstruction}->{documents}->{URL} = $args->{media_url};
    }
    my $response = $self->soap_post($self->updates_endpoint, 'CreateInstruction', 'xDoc', $self->_create_xml_string($data));

    my $resp_text = $response->valueof('//CreateInstructionResponse/CreateInstructionResult');
    if ($resp_text eq 'OK' || $resp_text =~ /Thank you for your feed back/) {
        return;
    } else {
        die $resp_text;
    }
}

sub get_updates {
    my ($self, $args) = @_;

    my $start_date = $self->format_datetime( $self->parse_w3c_datetime( $args->{start_date} ) );
    my $end_date = $self->format_datetime( $self->parse_w3c_datetime( $args->{end_date} ) );
    my $data = [
        SOAP::Data->name('startDate' => $start_date),
        SOAP::Data->name('endDate' => $end_date),
    ];
    my $response = $self->_soap_call($self->updates_endpoint, 'GetWdmUpdates', $data);

    my $xml = $response->valueof('//GetWdmUpdatesResponse/GetWdmUpdatesResult/NewDataSet');
    return [] unless $xml->{wdmupdate};
    my $updates = $xml->{wdmupdate};

    # a single updates returns a hashref not an array
    $updates = [ $updates ] unless ref $updates eq 'ARRAY';

    return $updates;
}

sub map_status {
    my ($self, $status) = @_;

    if ($self->config->{status_map}->{$status}) {
        $status = $self->config->{status_map}->{$status};
    }
    return $status;
}

sub soap_post {
    my ($self, $url, $method, $tag_name, $data) = @_;

    my $xml = SOAP::Data->type( xml => $data );
    my $soap_data = SOAP::Data->name($tag_name => \$xml);
    return $self->_soap_call($self->endpoint_url, $method, $soap_data);
}

sub _soap_call {
    my ($self, $url, $method, $data) = @_;
    my $soap = SOAP::Lite->new( encodingStyle => '' )->proxy( $self->endpoint_url, agent => '' ) ;
    $soap->default_ns('http://www.wdm.co.uk/remedy/');
    # avoid # in the SOAPAction header
    $soap->on_action(sub{sprintf '%s%s', @_ });
    my $som;
    if ( ref($data) eq 'ARRAY' ) {
        $som = $soap->call($method, @$data);
    } else {
        $som = $soap->call($method, $data);
    }
    return $som;
}


sub _create_xml_string {
    my ($self, $object) = @_;

    return # qq(<?xml version="1.0" encoding="utf-8"?>\n) .
        encode_utf8($self->xml->XMLout(
            $object
        ) );
}

sub _category_mapping {
    my ($self, $code) = @_;

    my $map = $self->config->{mappings}->{$code};

    return {
        category => $map->{category},
        'type' => $map->{type},
        detail => $map->{detail},
    };
};

1;
