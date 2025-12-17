package Open311::Endpoint::Integration::Verint;

use Moo;
use DateTime::Format::W3CDTF;
use Integrations::Verint;
use Digest::MD5 qw(md5_hex);
use MIME::Base64 qw(encode_base64);
use Path::Tiny;
use Tie::IxHash;
use URI::Split qw(uri_split);
use Open311::Endpoint::Service::UKCouncil;
use Open311::Endpoint::Service::Request::Update::mySociety;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::EndpointConfig';
with 'Role::Logger';

has jurisdiction_id => ( is => 'ro' );

has integration_class => (
    is => 'ro',
    default => 'Integrations::Verint',
);

has ua => (
    is => 'lazy',
    default => sub {
        LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter")
    },
);

sub get_integration {
    my $self = shift;
    my $integ = $self->integration_class;
    $integ = $integ->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->faultstring : $soap->transport->status, "\n"; });
    $integ->want_som(1);
    $integ->config_filename($self->jurisdiction_id);
    $self->log_identifier($self->jurisdiction_id);
    return $integ;
}

sub post_service_request {
    my ($self, $service, $args) = @_;

    die "No such service" unless $service;
    my $date = DateTime->now();

    my $services = $self->endpoint_config->{service_whitelist};
    my $service_cfg = $services->{$service->service_code};

    my $integ = $self->get_integration;

    my $title = $args->{attributes}->{title} . ' - FMS ID: ' . $args->{attributes}->{fixmystreet_id};
    my %extra;
    if ($service_cfg->{lob_system} eq 'M3') {
        my $comments =
            'Tell us about the problem: ' . $title
            . "\n\nProblem details: " . $args->{attributes}->{description};
        if ($args->{attributes}->{company_name}) {
            $comments .= "\n\nIf applicable, provide the name of the company responsible: " . $args->{attributes}->{company_name};
        }
        $comments .= "\n\nLink: " . $args->{attributes}->{report_url};
        $extra{m3_comments} = $comments;
    } elsif ($args->{attributes}->{company_name}) {
        $extra{txt_company_name} = $args->{attributes}->{company_name};
    }
    if ($service_cfg->{form_name} eq 'lbe_saftey_barrier_new') {
        $extra{dt_date_noticed_problem} = $date->date;
    }

    my $result = $integ->CreateRequest(
        $service_cfg->{form_name},
        ixhash(
            # Location
            le_gis_lat => $args->{lat},
            le_gis_lon => $args->{long},
            txt_easting => $args->{attributes}->{easting},
            txt_northing => $args->{attributes}->{northing},
            txt_map_usrn => $args->{attributes}->{usrn},
            txt_map_uprn => $args->{attributes}->{uprn},
            txt_location => $args->{attributes}->{uprn} ? 'Property' : 'Street',
            # Metadata
            txt_request_open_date => $date->datetime . "Z",
            le_typekey => $service_cfg->{typekey},
            txt_service_code => $service_cfg->{service_code},
            txt_lob_system => $service_cfg->{lob_system},
            # Person
            txt_cust_info_first_name => $args->{first_name},
            txt_cust_info_last_name => $args->{last_name},
            eml_cust_info_email => $args->{email},
            tel_cust_info_phone => $args->{phone},
            # Report
            txta_problem_details => $title,
            txta_problem => $args->{attributes}->{description},
            %extra,
        ),
        "Y"
    );
    die "Failed" unless $result;
    $result = $result->method;
    die "Failed" unless $result;
    my $status = $result->{status};
    my $ref = $result->{ref};
    die "$status $ref" unless $status eq 'success';

    my @photos;
    if (@{$args->{media_url}}) {
        foreach (@{$args->{media_url}}) {
            my $photo = $self->ua->get($_);
            my (undef, undef, $path) = uri_split($_);
            my $filename = path($path)->basename;
            my ($ext) = $filename =~ /\.([^.]*)$/;
            push @photos, [$filename, $photo->content, "image/$ext"];
        }
    } elsif (@{$args->{uploads}}) {
        foreach (@{$args->{uploads}}) {
            my $photo = path($_)->slurp;
            push @photos, [$_->basename, $photo, $_->content_type];
        }
    }
    foreach (@photos) {
        my $encoded = encode_base64($_->[1], '');
        my $result = $integ->AttachFileRequest($ref, $_->[0], $encoded, $_->[2], "txt_filename");
        # Log if failure? Nothing really can do at this point
    }

    return $self->new_request(
        service_request_id => $ref,
    )
}

sub get_service_request_updates {
    my ($self, $args) = @_;

    my $integ = $self->get_integration;
    my $mapping = $self->endpoint_config->{status_mapping};

    my $result = $integ->searchAndRetrieveCaseDetails(
        ixhash(
            'LastModifiedDateFrom' => $args->{start_date},
            'LastModifiedDateTo' => $args->{end_date},
        ),
        'all',
    );
    return unless $result;
    $result = $result->method;
    return unless $result;

    my $requests = $result->{FWTCaseFullDetails};
    $requests = [ $requests ] unless ref $requests eq 'ARRAY';
    my @updates;
    foreach (@$requests) {
        my $core = $_->{CoreDetails};
        my $closed = $core->{Closed};
        next unless $closed;
        my $reason = $core->{caseCloseureReason};
        my $status = 'closed';
        foreach (keys %$mapping) {
            if ($reason =~ /^$_/) {
                $status = $mapping->{$_};
            }
        }
        my $digest = substr(md5_hex($reason), 0, 8);

        my $refs = $core->{ExternalReferences}{ExternalReference};
        $refs = [ $refs ] unless ref $refs eq 'ARRAY';
        foreach my $ref (@$refs) {
            $ref =~ s/[^:\w_\-]//g;
            my $update_id = $ref . '_' . $digest;
            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new(
                status => $status,
                update_id => $update_id,
                service_request_id => $ref,
                description => '',
                updated_datetime => DateTime::Format::W3CDTF->parse_datetime($closed),
                extra => { latest_data_only => 1 },
            );
        }
    }
    return @updates;
}

=head2 services

This returns a list of Verint services from the service_whitelist.

=cut

sub services {
    my $self = shift;

    my $services = $self->endpoint_config->{service_whitelist};

    my @services = map {
        my $cfg = $services->{$_};
        my $name = $cfg->{name};
        my $service = Open311::Endpoint::Service::UKCouncil->new(
            service_name => $name,
            service_code => $_,
            description => $name,
            $cfg->{group} ? (group => $cfg->{group}) : (),
            allow_any_attributes => 1,
        );
        foreach (@{$cfg->{attributes} || []}) {
            if ($_->{type} eq 'notice') {
                push @{$service->attributes}, Open311::Endpoint::Service::Attribute->new({
                    code => $_->{code},
                    description => $_->{description},
                    variable => 0,
                    datatype => 'string',
                });
            } elsif ($_->{type} eq 'yn') {
                push @{$service->attributes}, Open311::Endpoint::Service::Attribute->new({
                    code => $_->{code},
                    description => $_->{description},
                    datatype => 'singlevaluelist',
                    required => 1,
                    values_sorted => [ 1, 0 ],
                    values => { 0 => 'No', 1 => 'Yes' },
                });
            } elsif ($_->{type} eq 'text') {
                push @{$service->attributes}, Open311::Endpoint::Service::Attribute->new({
                    code => $_->{code},
                    description => $_->{description},
                    datatype => 'string',
                    required => 0,
                });
            }
        }
        $service;
    } sort keys %$services;

    return @services;
}

sub ixhash {
    tie (my %data, 'Tie::IxHash', @_);
    return \%data;
}

1;
