package Open311::Endpoint::Integration::UK::EastHerts;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';

use Open311::Endpoint::Service::UKCouncil;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::Update;

#use SOAP::Lite;
use SOAP::Lite +trace => [ qw/method debug/ ];

use Integrations::EastHerts::Highways;

has jurisdiction_id => (
    is => 'ro',
    default => 'east_hertfordshire',
);

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    my $integ = Integrations::EastHerts::Highways->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->faultstring : $soap->transport->status, "\n"; });

    if ($args->{address_string}) {
        $args->{description} .= "\n\nLocation query entered: " . $args->{address_string};
    }

    my $attributes = $args->{attributes};
    if ($attributes->{car_details}) {
        $args->{description} .= "\n\nRegistration and make: " . $attributes->{car_details};
    }

    my $code = $service->service_code;
    if ($attributes->{code}) {
        $code = $attributes->{code};
    }
    my ($item_code, $subitem_code, $defect_code) = split /_/, $code;

    my $new_id = $integ->AddDefect({
        Easting => $attributes->{easting},
        Northing => $attributes->{northing},
        description => $args->{description},
        ItemCode => $item_code,
        SubItemCode => $subitem_code,
        DefectCode => $defect_code,
        GivenName => $args->{first_name},
        FamilyName => $args->{last_name},
        Email => $args->{email},
        TelephoneNumber => $args->{phone},
        ID => $attributes->{fixmystreet_id},
        photo => $args->{media_url},
    });

    my $request = $self->new_request(
        service_request_id => $new_id,
    );

    return $request;
}

sub post_service_request_update {
    my ($self, $args) = @_;

    my $integ = Integrations::EastHerts::Highways->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->faultstring : $soap->transport->status, "\n"; });

    my $request_id = $args->{service_request_id};

    my $description = $args->{description};
    if ($args->{media_url}) {
        $description .= "\n\n[ This update contains a photo, see: " . $args->{media_url} . " ]";
    }

    $integ->AddCallerToDefect($request_id, {
        GivenName => $args->{first_name},
        FamilyName => $args->{last_name},
        Email => $args->{email},
        # No telephone number provided
        ID => $args->{update_id},
        description => $description,
        # XXX What about status?
    });

    return Open311::Endpoint::Service::Request::Update->new(
        status => lc $args->{status},
        update_id => $args->{update_id},
    );
}

sub services {
    my @services = (
        [ 'Abandoned vehicles', 'SC_E_AVE' ],
        [ 'Dog Bin overflow', 'P_C_DBE' ],
        [ 'Dog fouling', 'SC_RS_DOG' ],
        [ 'Drugs Paraphernalia', 'ZZZDRUGS', 'Type', {
            CS_DP_ILS => 'Illegal Smoking',
            CS_DP_MED => 'Medicine Containers',
            CS_DP_OTS => 'Other substances (eg glue)',
            CS_DP_PHI => 'Phials or small bottles',
            CS_DP_SYR => 'Syringes & needles',
        } ],
        [ 'Litter', 'ZZZLITTER', 'Location', {
            SC_C_FSL => 'Footpath/Street',
            P_C_LPR => 'Parks & Open spaces',
        } ],
        [ 'Litter Bin overflow', 'ZZZLITTERBIN', 'Location', {
            SC_C_LBE => 'Footpath/Street',
            P_C_LBE => 'Parks & Open spaces',
        } ],
        [ 'Flyposting', 'SC_RS_FLP' ],
        [ 'Flytipping', 'SC_RS_FLY' ],
        [ 'Graffiti', 'ZZZGRAFFITI', 'Type', {
            SC_RS_GNO => 'non offensive',
            SC_RS_GRO => 'offensive',
        } ],
        [ 'Grass Cutting', 'P_C_GNC' ],
        [ 'Public toilets', 'SC_C_TOI' ],
        [ 'Street cleaning', 'ZZZSTREETCLEANING', 'Type', {
            SC_C_FSD => 'debris/mud',
            SC_C_FSL => 'litter'
        } ],
    );

    return map {
        my ($name, $code, $attrdesc, $values) = @$_;
        my %service = (
            service_name => $name,
            service_code => $code,
            description => $name,
        );
        my $service = Open311::Endpoint::Service::UKCouncil->new(%service);
        if ($name eq 'Abandoned vehicles') {
            push @{$service->attributes}, Open311::Endpoint::Service::Attribute->new(
                code => 'car_details',
                description => 'Registration and make',
                datatype => 'string',
                required => 1,
            );
        }
        if ($attrdesc) {
            push @{$service->attributes}, Open311::Endpoint::Service::Attribute->new(
                code => 'code',
                description => $attrdesc,
                datatype => 'singlevaluelist',
                required => 1,
                values => $values,
            );
        }
        $service;
    } @services;
}

__PACKAGE__->run_if_script;


sub make_soap_structure {
    my @out;
    for (my $i=0; $i<@_; $i+=2) {
        my $name = $_[$i];
        my $v = $_[$i+1];
        if (ref $v eq 'ARRAY') {
            my $type = shift @$v;
            push @out,
                SOAP::Data->name($name => [
                    SOAP::Data
                        ->name('item' => map { [ make_soap_structure(%$_) ] } @$v)
                        ->attr({'xsi:type' => $type})
                ])
                ->attr({'soapenc:arrayType' => "ro:$type" . "[]"});
        } else {
            push @out, SOAP::Data->name($name => $v);
        }
    }
    return @out;
}

sub SOAP::Serializer::as_StringArray {
    my ($self, $value, $name, $type, $attr) = @_;
    return [$name, {'xsi:type' => 'array', %$attr}, $value];
}

sub SOAP::Serializer::as_AddDefectStructure {
    my ($self, $value, $name, $type, $attr) = @_;

    my %hyperlinks;
    if ($value->{photo}) {
        $hyperlinks{Hyperlinks} = [
            'HyperlinkStructure',
            { URL => $value->{photo}, Description => "Report photo" },
        ];
    }

    my $elem = \SOAP::Data->value( make_soap_structure(
        StreetID => '005366',  # default
        # UniqueStreetReferenceNumber => '',
        Location => $value->{description},
        Coordinates => [
            'CoordinateStructure',
            { Easting => $value->{Easting}, Northing => $value->{Northing} },
        ],
        # PositionCode => '',
        ItemCode => $value->{ItemCode},
        SubItemCode => $value->{SubItemCode},
        DefectCode => $value->{DefectCode},
        # SeverityCode => '',
        # Quantity => 0,
        # Length => 0,
        # Width => 0,
        # Depth => 0,
        %hyperlinks,
        Caller => {
            Name => {
                # PersonNameTitle
                PersonGivenName => $value->{GivenName},
                PersonFamilyName => $value->{FamilyName},
            },
            ContactDetails => {
                Email => $value->{Email},
                TelephoneNumber => $value->{TelephoneNumber},
            },
            ExternalReference => $value->{ID},
            RecordedBy => 'FixMyStreet',
            SourceCode => 'FMS',  # Appears to be truncated to 5 chars?
        },
    ));
    return [$name, {'xsi:type' => 'ro:AddDefectStructure', %$attr}, $elem];
}

sub SOAP::Serializer::as_CallerStructure {
    my ($self, $value, $name, $type, $attr) = @_;

    my $elem = \SOAP::Data->value( make_soap_structure(
        Name => {
            # PersonNameTitle
            PersonGivenName => $value->{GivenName},
            PersonFamilyName => $value->{FamilyName},
        },
        ContactDetails => {
            Email => $value->{Email},
            TelephoneNumber => $value->{TelephoneNumber},
        },
        ExternalReference => $value->{ID},
        RecordedBy => 'FixMyStreet',
        AdditionalDetails => $value->{description},
        SourceCode => 'FMS', # Appears to be truncated to 5 chars?
    ));
    return [$name, {'xsi:type' => 'ro:CallerStructure', %$attr}, $elem];
}
