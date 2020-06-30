package Open311::Endpoint::Integration::Bartec;

use JSON::MaybeXS;
use Path::Tiny;
use YAML::XS qw(LoadFile);
use MIME::Base64;

use Integrations::Bartec;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::Logger';

use Open311::Endpoint::Service::UKCouncil::Bartec;
use Open311::Endpoint::Service::Request::Update::mySociety;
use Open311::Endpoint::Service::Request::ExtendedStatus;

has jurisdiction_id => (
    is => 'ro',
);

has bartec => (
    is => 'lazy',
    default => sub { Integrations::Bartec->new(config_filename => $_[0]->jurisdiction_id) }
);

has integration_class => (
    is => 'ro',
    default => 'Integrations::Bartec'
);

has allowed_services => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my %allowed = map { uc $_ => 1 } @{ $self->get_integration->config->{allowed_services} };
        return \%allowed;
    }
);

sub get_integration {
    my $self = shift;
    my $integ = $self->integration_class->new;
    $integ->config_filename($self->jurisdiction_id);
    return $integ;
}

sub services {
    my $self = shift;
    my $services = $self->get_integration->ServiceRequests_Types_Get;
    $services = $self->_coerce_to_array( $services, 'ServiceType' );
    my @services = map {
        $_->{Description} =~ s/(.)(.*)/\U$1\L$2/;
        $_->{ServiceClass}->{Description} =~ s/(.)(.*)/\U$1\L$2/;
        my $service = Open311::Endpoint::Service::UKCouncil::Bartec->new(
            service_name => $_->{Description},
            service_code => $_->{ID},
            description => $_->{Description},
            groups => [ $_->{ServiceClass}->{Description} ],
      );
    } grep { $self->allowed_services->{uc $_->{Description}} } @$services;
    return @services;
}

sub service {
    my ($self, $id, $args) = @_;

    my @services = grep { $_->service_code eq $id } $self->services;

    return $services[0];
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    my $integ = $self->get_integration;
    my $config = $integ->config;

    $args->{uprn} = $self->get_nearest_uprn($args);

    my $defaults = $config->{field_defaults} || {};
    my $req = {
        %$defaults,
        %$args
    };

    my $res = $integ->ServiceRequests_Create($service, $req);
    die "failed to send" unless $res->{ServiceCode};



    if ( @{ $args->{media_url} }) {
        my $sr = $integ->ServiceRequests_Get( $res->{ServiceCode} );
        $self->upload_attachments($sr->{ServiceRequest}->{id}, $args); # XXX not sure ServiceCode is correct
    }

    return $self->new_request(
        service_request_id => $res->{ServiceCode}
    );
}

sub get_nearest_uprn {
    my ($self, $args) = @_;

    my $conf = $self->get_integration->config;

    my $uprn;

    my $lookup_type = $conf->{uprn_lookup}->{ $args->{service_code } };
    if ( $lookup_type && $lookup_type eq 'USRN' && $args->{attributes}->{site_code} ) {
        $uprn = $self->get_uprn_for_street( $args->{attributes}->{site_code} );
    } else {
        $uprn = $self->get_uprn_for_location( $args );
    }

    return $uprn;
}


sub get_uprn_for_street {
    my ($self, $usrn) = @_;

    my $uprn;

    my $premises = $self->get_integration->Premises_Get({
        usrn => $usrn,
    });

    if (ref $premises->{Premises} eq 'ARRAY') {
        for my $p ( @{ $premises->{Premises} } ) {
            next unless $p->{Address}->{Address1} eq 'STREET RECORD';

            return $p->{UPRN};
        }
    }
}

sub get_uprn_for_location {
    my ($self, $args) = @_;

    my $bbox = $self->bbox_from_coords( $args->{lat}, $args->{long} );

    my $premises = $self->get_integration->Premises_Get({
        bbox => $bbox,
        usrn => $args->{attributes}->{site_code},
        postcode => $args->{attributes}->{postcode},
        address => $args->{attributes}->{house_no},
        street => $args->{attributes}->{street}
    });

    my $uprn;
    my $address_matches = $self->get_integration->config->{address_match}->{ $args->{service_code} };
    # if we've got more than one result loop over them to get the closest
    if (ref $premises->{Premises} eq 'ARRAY') {
        my $matches = { all => { uprn => '', min => 999 }, address => { uprn => '', min => 999 } };
        my $i = 1;

        # we need to loop over it this way in order to access the attributes
        # but also count where we are so we can get the value of the matching
        # premises.
        for my $result ( $premises->{SOM}->dataof('//Premises/Location/Metric') ) {
            my ($lat, $lon) = ( $result->attr->{Latitude}, $result->attr->{Longitude} );
            my $dist = $self->distance_haversine( [ $lat, $lon ], [ $args->{lat}, $args->{long} ] );

            my $p = $premises->{SOM}->valueof("//Premises_GetResult/[$i]");
            if ( grep { $p->{Address}->{Address1} =~ /$_/ } @$address_matches ) {
                if ( $dist < $matches->{address}->{min} ) {
                    $matches->{address}->{min} = $dist;
                    $matches->{address}->{uprn} = $p->{UPRN};
                }
            } elsif ( $dist < $matches->{all}->{min} ) {
                $matches->{all}->{min} = $dist;
                $matches->{all}->{uprn} = $p->{UPRN};
            }
            $i++;
        }
        $uprn = $matches->{address}->{uprn} ? $matches->{address}->{uprn} : $matches->{all}->{uprn};
    } else {
        $uprn = $premises->{Premises}->{UPRN};
    }

    return $uprn;
}

# generate a rough 100m square bounding box centred on the report
sub bbox_from_coords {
    my ($self, $lat, $long) = @_;

    # roughly 50 meters
    my $lat_delta = 0.000438;
    my $lon_delta = 0.000736;

    my $max_lat = $lat + $lat_delta;
    my $min_lat = $lat - $lat_delta;

    my $max_lon = $long + $lon_delta;
    my $min_lon = $long - $lon_delta;

    return { max => { lat => $max_lat, lon => $max_lon }, min => { lat => $min_lat, lon => $min_lon } };
}


# maths utility functions
sub deg2rad { my $degrees = shift; return ($degrees / 180) * 3.14159265358979; }
sub asin { atan2($_[0], sqrt(1 - $_[0] * $_[0])) }

=for comment
    Calculate the great circle distance between two points 
    on the earth (specified in decimal degrees)
    Haversine
    formula: 
        a = sin²(Δφ/2) + cos φ1 ⋅ cos φ2 ⋅ sin²(Δλ/2)
                        _   ____
        c = 2 ⋅ atan2( √a, √(1−a) )
        d = R ⋅ c

    where   φ is latitude, λ is longitude, R is earth’s radius (mean radius = 6,371km);
            note that angles need to be in radians to pass to trig functions!
=cut

sub distance_haversine {
    my ($self, $p1, $p2) = @_;
    my ($lat1, $lon1) = @$p1;
    my ($lat2, $lon2) = @$p2;

    my $r = 6371; # km - earths's radius

    # convert decimal degrees to radians
    ($lat1, $lon1, $lat2, $lon2)  = map { deg2rad( $_ ) } ($lat1, $lon1, $lat2, $lon2);

    # haversine formula 
    my $dlon = $lon2 - $lon1;
    my $dlat = $lat2 - $lat1;

    $a = sin($dlat/2)**2 + cos($lat1) * cos($lat2) * sin($dlon/2)**2;
    my $c = 2 * asin(sqrt($a));
    my $d = $r * $c;
    return $d;
}

sub get_service_request_updates {
    my ($self, $args) = @_;

    my $w3c = DateTime::Format::W3CDTF->new;

    my $response = $self->get_integration->ServiceRequests_Updates_Get($args->{start_date});

    my @updates;
    my $updates = $self->_coerce_to_array( $response, 'ServiceRequest_Updates' );
    for my $update ( @$updates ) {
        my $history = $self->get_integration->ServiceRequests_History_Get( $update->{ServiceRequestID}, $args->{start_date} );

        next unless $history->{ServiceRequest_History};
        my $entries = $self->_coerce_to_array( $history, 'ServiceRequest_History' );

        for my $entry ( @$entries ) {
            my %args = (
                status => $self->get_integration->config->{status_map}->{ $entry->{ServiceStatusName} },
                update_id => $entry->{id},
                service_request_id => $entry->{ServiceCode},
                description => '',
                updated_datetime => $w3c->parse_datetime( $entry->{DateChanged} )->truncate( to => 'second')->set_time_zone('Europe/London'),
            );

            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new ( %args );
        }

    }
    return @updates;
}

sub get_service_requests {
    my ($self, $args) = @_;

    my $w3c = DateTime::Format::W3CDTF->new;

    my $response = $self->get_integration->ServiceRequests_Updates_Get($args->{start_date});

    my @requests;

    my $updates = $self->_coerce_to_array( $response, 'ServiceRequest_Updates' );
    for my $update ( @$updates ) {
        my $res = $self->get_integration->ServiceRequests_Get( $update->{ServiceCode} );

        next unless $res;
        my $sr = $res->{ServiceRequest};
        # if it's got an external reference it's an FixMyStreet report. And ignore reports
        # that are in any state other than open as it's assumed they are not new.
        next if $sr->{ExternalReference} or not $sr->{ServiceStatus}->{Status} eq 'OPEN';

        my $service_name = $sr->{ServiceType}->{Description};
        next unless $self->allowed_services->{uc $service_name};
        $service_name = "\u\L$service_name";

        my $location = $res->{SOM}->dataof('//ServiceLocation/Metric');

        my $date = $w3c->parse_datetime( $sr->{DateRequested} )->truncate( to => 'second' );
        $date->set_time_zone('Europe/London');
        my %args = (
            service_request_id => $sr->{ServiceCode},
            requested_datetime => $date,
            updated_datetime => $date,

            status => 'open',
            latlong => [ $location->attr->{Latitude}, $location->attr->{Longitude} ],
        );

        my $service = Open311::Endpoint::Service->new(
            service_name => $service_name,
            service_code => $sr->{ServiceType}->{ID},
        );

        $args{service} = $service;

        push @requests, Open311::Endpoint::Service::Request::ExtendedStatus->new( %args );
    }

    return @requests;
}

sub upload_attachments {
    my ($self, $request_id, $args) = @_;

    # grab the URLs and download its content
    my $photos = $self->_get_photos( $args->{media_url} );

    for my $photo ( @$photos ) {
        (my $photo_id = $photo->filename) =~ s/^\d+\.(\d+)\..*$/$1/;
        $photo_id = $args->{attributes}->{fixmystreet_id} . $photo_id;
        $self->get_integration->Service_Request_Document_Create({
            srid => $request_id,
            id => $photo_id + 1,
            name => $photo->filename,
            content => MIME::Base64::encode_base64( $photo->content, '' )
        });

    }
}

sub _get_photos {
    my ($self, $urls) = @_;

    # Grab each photo from FMS
    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    my @photos = map {
        $ua->get($_);
    } @$urls;

    return \@photos;
}

sub _coerce_to_array {
    my ( $self, $ref, $key ) = @_;

    $ref = ref $ref->{$key} eq 'ARRAY' ? $ref->{$key} : [ $ref->{$key} ] ;

    return $ref;
}

__PACKAGE__->run_if_script;
