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

has non_unique_services => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my %non_unique = map { uc $_ => 1 } @{ $self->get_integration->config->{non_unique_services} };
        return \%non_unique;
    }
);

has service_map => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $map = $self->get_integration->config->{service_map};
        my %service_map;
        foreach my $class ( keys %$map ) {
            $service_map{ uc $class } = {
                map { uc $_ => $map->{$class}->{ $_ } } keys %{ $map->{$class} }
            };
        }
        return \%service_map;
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
        my ($service_name, $class) = $self->_get_service_name($_);

        my $service = Open311::Endpoint::Service::UKCouncil::Bartec->new(
            service_name => $service_name,
            service_code => $_->{ID},
            description => $_->{Description},
            groups => [ $class ],
      );
    } grep { $self->_allowed_service($_) } @$services;
    return @services;
}

sub _get_service_name {
    my ($self, $service) = @_;

    $service->{Description} =~ s/(.)(.*)/\U$1\L$2/;
    (my $class = $service->{ServiceClass}->{Description}) =~ s/(.)(.*)/\U$1\L$2/;
    my $service_name = $service->{Description};

    # service type names are not unique in bartec so need to distinguish
    # them
    if ($self->non_unique_services->{uc $service_name}) {
       $service_name .= " ($class)",
    }

    # some things we want to handle are set up as service classes so
    # map those back to categories
    if ( $self->service_map->{uc $class} &&
         $self->service_map->{uc $class}->{uc $service_name}
    ) {
        my $map = $self->service_map->{uc $class}->{uc $service_name};
        $class = $map->{group};
        $service_name = $map->{category};
        $service->{Description} = $service_name;
    }

    return ($service_name, $class);
}

sub _allowed_service {
    my ($self, $service) = @_;

    return 1 if $self->allowed_services->{uc $service->{Description}} ||
                (
                    $self->service_map->{uc $service->{ServiceClass}->{Description}} &&
                    $self->service_map->{uc $service->{ServiceClass}->{Description}}->{uc $service->{Description}}
                );

    return 0;
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

    # remove cruft
    $args->{attributes}->{closest_address} =~ s/^Nearest[^:]*: //;
    $args->{attributes}->{closest_address} =~ s/\nNearest.*$//s;

    my $defaults = $config->{field_defaults} || {};
    my $req = {
        %$defaults,
        %$args
    };

    my $res = $integ->ServiceRequests_Create($service, $req);
    unless ($res->{ServiceCode}) {
        my $err = $res->{Errors}->{Message};
        die "failed to send request " . $args->{attributes}->{fixmystreet_id} . ": $err";
    }

    my $sr = $integ->ServiceRequests_Get( $res->{ServiceCode} );

    $self->_attach_note( $args, $sr );

    if ( @{ $args->{media_url} }) {
        $self->upload_urls($sr->{ServiceRequest}->{id}, $args); # XXX not sure ServiceCode is correct
    } elsif ( @{ $args->{uploads} } ) {
        $self->upload_attachments($sr->{ServiceRequest}->{id}, $args); # XXX not sure ServiceCode is correct
    }

    return $self->new_request(
        service_request_id => $res->{ServiceCode}
    );
}

sub _attach_note {
    my ($self, $args, $sr) = @_;

    my $integ = $self->get_integration;

    my $type = $integ->note_types->{ $integ->config->{note_types}->{report} };

    my $note = $args->{attributes}->{title} . "\n\n" . $args->{attributes}->{description};

    if ($args->{attributes}->{central_asset_id}) {
        my $asset_details = "\n\nAsset id: " . $args->{attributes}->{central_asset_id} . "\n" .
                            "Asset detail: " . $args->{attributes}->{asset_details};

        $note .= $asset_details;
    }

    my $res = $integ->ServiceRequests_Notes_Create({
        srid => $sr->{ServiceRequest}->{id},
        note_type => $type,
        note => $note,
    });

    if ( $res->{Errors}->{Message} ) {
        warn "failed to attach note for report "
            . $args->{attributes}->{fixmystreet_id}
            . ": " . $res->{Errors}->{Message};
    }
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
                status => $self->_get_update_status($entry),
                update_id => $entry->{id},
                service_request_id => $entry->{ServiceCode},
                description => '',
                updated_datetime => $w3c->parse_datetime( $entry->{DateChanged} )->truncate( to => 'second')->set_time_zone('Europe/London'),
            );

            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new ( %args );
        }

    }
    return sort { $a->update_id <=> $b->update_id } @updates;
}

sub _get_update_status {
    my ($self, $update) = @_;

    my $conf = $self->get_integration->config;

    my $status = $conf->{status_map}->{ $update->{ServiceStatusName} };

    my $mapped = $conf->{closing_code_map}->{ $update->{ServiceStatusName} }->{ $update->{ClosingCode} };
    return $mapped if $mapped && $update->{ClosingCode};

    return $status;
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

        next if $self->skip_request($sr);

        next unless $self->_allowed_service($sr->{ServiceType});
        my ($service_name) = $self->_get_service_name($sr->{ServiceType});

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

# if it's got an external reference it's an FixMyStreet report. And ignore reports
# that are in any state other than open as it's assumed they are not new.
sub skip_request {
    my ($self, $sr) = @_;
    my $skip = 0;

    if ( $sr->{ExternalReference} ||
         not grep { $sr->{ServiceStatus}->{Status} eq $_ } @{ $self->get_integration->config->{statuses_to_fetch} } ) {
         $skip = 1;
    }

    return $skip;
}

sub upload_urls {
    my ($self, $request_id, $args) = @_;

    # grab the URLs and download its content
    my $photos = $self->_get_photos( $args->{media_url} );

    my @photos = map {
        {
            filename => $_->filename,
            data => MIME::Base64::encode_base64($_->content, ''),
        }
    } @$photos;

    $self->_put_photos($request_id, $args, \@photos);
}

sub upload_attachments {
    my ($self, $request_id, $args) = @_;

    my @photos = map {
        my $file = path($_);
        {
            filename => $_->filename,
            data => MIME::Base64::encode_base64($file->slurp, '')
        };
    } @{ $args->{uploads} };

    $self->_put_photos($request_id, $args, \@photos);
}

sub _put_photos {
    my ($self, $request_id, $args, $photos) = @_;

    my $photo_id = $args->{attributes}->{fixmystreet_id};
    my $i = 1;
    for my $photo ( @$photos ) {
        my $res = $self->get_integration->Service_Request_Document_Create({
            srid => $request_id,
            id => $photo_id . $i,
            name => $photo->{filename},
            content => $photo->{data},
        });
        if ( $res->{Errors}->{Message} ) {
            warn "failed to attach photo for report "
                . $args->{attributes}->{fixmystreet_id}
                . ": " . $res->{Errors}->{Message};
        }
        $i++;
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

    return [] unless $ref->{$key};

    $ref = ref $ref->{$key} eq 'ARRAY' ? $ref->{$key} : [ $ref->{$key} ] ;

    return $ref;
}

__PACKAGE__->run_if_script;
