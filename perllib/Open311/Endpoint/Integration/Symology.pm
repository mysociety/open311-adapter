package Open311::Endpoint::Integration::Symology;

use v5.14;
use warnings;

use DateTime::Format::Strptime;
use DateTime::Format::W3CDTF;
use Digest::MD5 qw(md5_hex);
use Moo;
use JSON::MaybeXS;
use Text::CSV;
use YAML::Logic;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::EndpointConfig';
with 'Role::Logger';

use Integrations::Symology;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::Update::mySociety;
use Open311::Endpoint::Service::UKCouncil::Symology;

has jurisdiction_id => ( is => 'ro' );

has date_formatter => ( is => 'lazy', default => sub {
    DateTime::Format::Strptime->new(
        pattern => '%d/%m/%Y %H:%M',
        time_zone => 'Europe/London',
    );
});

has category_mapping => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{category_mapping} }
);

has username => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{username} }
);

has update_urls => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{update_urls} }
);

has customer_defaults => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{customer_defaults} }
);

has request_defaults => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{request_defaults} }
);

has external_id_prefix => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{external_id_prefix} || "" }
);

# May want something like Confirm's service_assigned_officers

sub services {
    my $self = shift;
    my $services = $self->category_mapping;
    my @services = map {
        my $name = $services->{$_}{name};
        my $service = $self->service_class->new(
            service_name => $name,
            service_code => $_,
            description => $name,
            $services->{$_}{group} ? (group => $services->{$_}{group}) : (),
            $services->{$_}{groups} ? (groups => $services->{$_}{groups}) : (),
        );
        foreach (@{$services->{$_}{questions}}) {
            my %attribute = (
                code => $_->{code},
                description => $_->{description},
            );
            if ($_->{variable} // 1) {
                $attribute{required} = 1;
            } else {
                $attribute{variable} = 0;
                $attribute{required} = 0;
            }
            if ($_->{values}) {
                $attribute{datatype} = 'singlevaluelist';
                $attribute{values} = { map { $_ => $_ } @{$_->{values}} };
            } else {
                $attribute{datatype} = 'string';
            }
            push @{$service->attributes}, Open311::Endpoint::Service::Attribute->new(%attribute);
        }
        $service;
    } keys %$services;
    return @services;
}

sub service_class {
    'Open311::Endpoint::Service::UKCouncil::Symology';
}

sub process_service_request_args {
    my $self = shift;
    my $args = shift;

    my $service_code = $args->{service_code};
    my $codes = $self->category_mapping->{$service_code};
    die "Could not find category mapping for $service_code\n" unless $codes;

    my $request = {
        %{$self->request_defaults || {}},
        Description => $args->{description},
        UserName => $self->username,
        %{$codes->{parameters}},
    };

    # We need to bump some values up from the attributes hashref to
    # the $args passed
    foreach (qw/fixmystreet_id easting northing UnitID RegionSite NSGRef contributed_by/) {
        if (defined $args->{attributes}->{$_}) {
            $request->{$_} = delete $args->{attributes}->{$_};
        }
    }

    $request->{fixmystreet_id} = $self->external_id_prefix . $request->{fixmystreet_id};

    if ($args->{media_url}->[0]) {
        foreach my $photo_url (@{ $args->{media_url} }) {
            $request->{Description} .= "\n\n[ This report contains a photo, see: " . $photo_url . " ]";
        }
    }

    if ($args->{report_url}) {
        $request->{Description} .= "\n\nView report on FixMyStreet: $args->{report_url}";
    }

    if ($args->{address_string}) {
        $request->{Description} .= "\n\nLocation query entered: " . $args->{address_string};
    }

    # We then need to add all other attributes to the Description
    my %attr_lookup;
    my %ignore;
    foreach (@{$codes->{questions}}) {
        my $code = $_->{code};
        my $variable = $_->{variable} // 1;
        $ignore{$code} = 1 unless $variable;
        $attr_lookup{$code} = $_->{description};
    }
    foreach (sort keys %{$args->{attributes}}) {
        next if $ignore{$_};
        my $key = $attr_lookup{$_} || $_;
        $request->{Description} .= "\n\n$key: " . $args->{attributes}->{$_};
    }

    my $logic = YAML::Logic->new();
    foreach (@{$codes->{logic}}) {
        die unless @{$_->{rules}} %2 == 0; # Must be even
        if ($logic->evaluate($_->{rules}, {
          attr => $args->{attributes},
          request => $request
        })) {
            $request = { %$request, %{$_->{output}} };
        }
    }

    # Bit Bexley-specific still
    my $contact_type = $self->customer_defaults->{ContactType};
    $contact_type //= $request->{contributed_by} ? 'TL' : 'OL';

    my $customer = {
        name => $args->{first_name} . " " . $args->{last_name},
        email => $args->{email},
        phone => $args->{phone},
        customer_type => $self->customer_defaults->{CustomerType},
        contact_type => $contact_type,
    };

    my $fields = delete $request->{contributed_by};

    return ($request, $customer, $fields);
}

has integration_class => (
    is => 'ro',
    default => 'Integrations::Symology'
);

sub get_integration {
    my $self = shift;
    my $integ = $self->integration_class;
    $integ = $integ->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->faultstring : $soap->transport->status, "\n"; });
    $integ->config_filename($self->jurisdiction_id);
    return $integ;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service\n" unless $service;

    my @args = $self->process_service_request_args($args);
    $self->logger->debug(encode_json(\@args));

    my $response = $self->get_integration->send_request(@args);

    my $crno = $self->check_error($response, 'SendRequest');

    my $request = $self->new_request(
        service_request_id => $crno,
    );

    return $request;
}

sub process_service_request_update_args {
    my ($self, $args) = @_;

    my $service_code = $args->{service_code};
    my $codes = $self->category_mapping->{$service_code};
    die "Could not find category mapping for $service_code\n" unless $codes;

    my $closed = $args->{status} =~ /FIXED|DUPLICATE|NOT_COUNCILS_RESPONSIBILITY|NO_FURTHER_ACTION|INTERNAL_REFERRAL|CLOSED/;

    my $request = {
        closed => $closed,
        Description => $args->{description},
        ServiceCode => $codes->{parameters}{ServiceCode},
        CRNo => $args->{service_request_id},
        fixmystreet_id => $self->external_id_prefix . $args->{service_request_id_ext},
        UserName => $self->username,
    };
    $request->{EventType} = $self->event_action_event_type($request);

    if ($args->{media_url}->[0]) {
        $request->{Description} .= "\n\n[ This update contains a photo, see: " . $args->{media_url}->[0] . " ]";
    }

    if ($args->{nsg_ref}) {
        $request->{NextAction} = $self->post_add_next_action_update($args->{nsg_ref});
    }

    return $request;
}

sub post_service_request_update {
    my ($self, $args) = @_;

    my @args = $self->process_service_request_update_args($args);
    $self->logger->debug(encode_json(\@args));

    my $response = $self->get_integration->send_update(@args);

    $self->check_error($response, 'SendEventAction');

    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => lc $args->{status},
        update_id => $args->{update_id},
    );
}

sub check_error {
    my ($self, $response, $type) = @_;

    die "Couldn't create $type in Symology\n" unless defined $response;

    $self->logger->debug(encode_json($response));

    # StatusCode is 0 on success, but we can get failures and still create an
    # entry, in which case there is no point trying again, so look for creation.
    my $crno;
    my $error = $response->{StatusMessage};
    my $result = $response->{$type."Results"}->{$type."ResultRow"};
    $result = [ $result ] if ref $result ne 'ARRAY';
    foreach (@$result) {
        if ($_->{RecordType}) {
            $error .= " - $_->{MessageText}" if $_->{RecordType} == 1;
            if ($_->{RecordType} == 2 && $type eq 'SendRequest') {
                $crno = $_->{ConvertCRNo};
                $error .= " - created request $crno";
            }
        }
    }

    if (($response->{StatusCode}//-1) == 0 || $crno) {
        $self->logger->debug("Created $type in Symology: $error");
        return $crno; # For reports, not updates
    } else {
        die "Couldn't create $type in Symology: $error\n";
    }
}

sub _get_csvs {
    my $self = shift;
    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    my @csv_files = map { $ua->get($_) } @{$self->update_urls};
    @csv_files = map { $_->content_ref } @csv_files;
    return \@csv_files;
}

sub get_service_request_updates {
    my ($self, $args) = @_;

    my $w3c = DateTime::Format::W3CDTF->new;
    my $start_time = $w3c->parse_datetime($args->{start_date});
    my $end_time = $w3c->parse_datetime($args->{end_date});

    my %seen;
    my @updates;
    my $csv_files = $self->_get_csvs;
    foreach (@$csv_files) {
        open my $fh, '<', $_;

        my $csv = Text::CSV->new;
        $csv->header($fh, { munge_column_names => {
            "History Date/Time" => "date_history",
        } });

        while (my $row = $csv->getline_hr($fh)) {
            next unless $row->{CRNo} && $row->{date_history};
            my $dt = $self->date_formatter->parse_datetime($row->{date_history});
            next unless $dt >= $start_time && $dt <= $end_time;

            my ($update, $id) = $self->_process_csv_row($row, $dt);
            # The same row might appear in multiple files (e.g. for Central Beds
            # each 30 minute CSV contains 90 minutes of data) so skip if we've
            # already seen this row.
            next if !$update || $seen{$id};

            push @updates, $update;
            $seen{$id} = 1;
        }
    }

    $self->post_process_csvs(\@updates, $start_time, $end_time);

    return @updates;
}

sub post_process_csvs { }

sub _process_csv_row {
    my ($self, $row, $dt) = @_;
    my $crno = $row->{CRNo};

    my $digest_key = join "-", map { $row->{$_} || '' } sort keys %$row;
    my $digest = substr(md5_hex($digest_key), 0, 8);
    my $update_id = $crno . '_' . $digest;

    my $update = $self->_create_update_object($row, $row->{CRNo}, $dt, $update_id);
    return ($update, $update->update_id) if $update;
}

sub _create_update_object {
    my ($self, $row, $crno, $dt, $update_id) = @_;

    my ($status, $external_status) = $self->_update_status($row);
    return unless $status;
    my $description = $self->_update_description($row);

    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => $status,
        update_id => $update_id,
        service_request_id => $crno+0,
        description => $description,
        updated_datetime => $dt,
        $external_status ? ( external_status_code => $external_status ) : (),
    );
}

1;
