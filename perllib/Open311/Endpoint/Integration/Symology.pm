package Open311::Endpoint::Integration::Symology;

use v5.14;
use warnings;

use DateTime::Format::Strptime;
use DateTime::Format::W3CDTF;
use Digest::MD5 qw(md5_hex);
use Moo;
use Path::Tiny;
use JSON::MaybeXS;
use Text::CSV;
use YAML::XS qw(LoadFile);
use YAML::Logic;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::Logger';

use Integrations::Symology;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::Update::mySociety;
use Open311::Endpoint::Service::UKCouncil::Symology;

has jurisdiction_id => ( is => 'ro' );

has endpoint_config => ( is => 'lazy' );

has date_formatter => ( is => 'lazy', default => sub {
    DateTime::Format::Strptime->new(
        pattern => '%d/%m/%Y %H:%M',
        time_zone => 'Europe/London',
    );
});

sub _build_endpoint_config {
    my $self = shift;
    my $config_file = path(__FILE__)->parent(5)->realpath->child('conf/council-' . $self->jurisdiction_id . '.yml');
    my $conf = LoadFile($config_file);
    return $conf;
}

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

sub log_and_die {
    my ($self, $msg) = @_;
    $self->logger->error($msg);
    die "$msg\n";
}

sub process_service_request_args {
    my $self = shift;
    my $args = shift;

    my $service_code = $args->{service_code};
    my $codes = $self->category_mapping->{$service_code};
    $self->log_and_die("Could not find category mapping for $service_code") unless $codes;

    my $request = {
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

    my $customer = {
        name => $args->{first_name} . " " . $args->{last_name},
        email => $args->{email},
        phone => $args->{phone},
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
    $self->log_and_die("No such service") unless $service;

    my @args = $self->process_service_request_args($args);
    $self->logger->debug(encode_json(\@args));

    my $response = $self->get_integration->SendRequestAdditionalGroup(
        undef, # Not needed
        @args
    );

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
    $self->log_and_die("Could not find category mapping for $service_code") unless $codes;

    my $closed = $args->{status} =~ /FIXED|DUPLICATE|NOT_COUNCILS_RESPONSIBILITY|NO_FURTHER_ACTION|INTERNAL_REFERRAL|CLOSED/;

    my $request = {
        closed => $closed,
        Description => $args->{description},
        ServiceCode => $codes->{parameters}{ServiceCode},
        CRNo => $args->{service_request_id},
        fixmystreet_id => $args->{service_request_id_ext},
        UserName => $self->username,
    };
    $request->{EventType} = $self->event_action_event_type($request);

    if ($args->{media_url}->[0]) {
        $request->{Description} .= "\n\n[ This update contains a photo, see: " . $args->{media_url}->[0] . " ]";
    }

    return $request;
}

sub post_service_request_update {
    my ($self, $args) = @_;

    my @args = $self->process_service_request_update_args($args);
    $self->logger->debug(encode_json(\@args));

    my $response = $self->get_integration->SendEventAction(
        undef, # Not needed
        @args
    );

    $self->check_error($response, 'SendEventAction');

    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => lc $args->{status},
        update_id => $args->{update_id},
    );
}

sub check_error {
    my ($self, $response, $type) = @_;

    $self->log_and_die("Couldn't create $type in Symology") unless defined $response;

    $self->logger->debug(encode_json($response));

    # StatusCode is 0 on success, but we can get failures and still create an
    # entry, in which case there is no point trying again, so look for creation.
    my $crno;
    my $error = $response->{StatusMessage};
    my $result = $response->{$type."Results"}->{$type."ResultRow"};
    $result = [ $result ] if ref $result ne 'ARRAY';
    foreach (@$result) {
        $error .= " - $_->{MessageText}" if $_->{RecordType} == 1;
        if ($_->{RecordType} == 2 && $type eq 'SendRequest') {
            $crno = $_->{ConvertCRNo};
            $error .= " - created request $crno";
        }
    }

    if (($response->{StatusCode}//-1) == 0 || $crno) {
        $self->logger->debug("Created $type in Symology: $error");
        return $crno; # For reports, not updates
    } else {
        $self->log_and_die("Couldn't create $type in Symology: $error");
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

    my @updates;
    my $csv_files = $self->_get_csvs;
    foreach (@$csv_files) {
        open my $fh, '<', $_;

        my $csv = Text::CSV->new;
        $csv->header($fh, { munge_column_names => {
            "History Date/Time" => "date_history",
        } });

        while (my $row = $csv->getline_hr($fh)) {
            my $dt = $self->date_formatter->parse_datetime($row->{date_history});
            next unless $dt >= $start_time && $dt <= $end_time;

            push @updates, $self->_process_csv_row($row);
        }
    }

    return @updates;
}

sub _process_csv_row {
    my ($self, $row) = @_;

    my $dt = $self->date_formatter->parse_datetime($row->{date_history});

    my $status = do {
        my $maint_stage = $row->{'Maint. Stage'} || '';
        my $action_due = $row->{'Action Due'} || '';
        if ($maint_stage eq 'ORDERED') {
            'investigating'
        } elsif ($maint_stage eq 'COMMENCED' || $maint_stage eq 'ALLOCATED') {
            'action_scheduled'
        } elsif ($maint_stage =~ /COMPLETED|CLAIMED|APPROVED/) {
            'fixed'
        } elsif ($action_due eq 'CLEARREQ') {
            'no_further_action'
        } elsif ($action_due eq 'CR') {
            'fixed'
        } elsif ($action_due =~ /^[NS][1-6]$/) {
            'in_progress'
        } elsif ($action_due eq 'IR') {
            'internal_referral'
        } elsif ($action_due eq 'NCR') {
            'not_councils_responsibility'
        } elsif ($action_due =~ /^([NS]I[1-6]MOB|IPSGM|IGF|IABV)$/) {
            'investigating'
        } elsif ($action_due =~ /^PT[CS]$/) {
            'action_scheduled'
        } elsif ($row->{Stage} == 9) {
            'IGNORE'
        } else {
            'open' # XXX Might want to maintain existing status?
        }
    };
    return if $status eq 'IGNORE';

    my $digest_key = join "-", map { $row->{$_} } sort keys %$row;
    my $digest = substr(md5_hex($digest_key), 0, 8);
    my $update_id = $row->{CRNo} . '_' . $digest;
    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => $status,
        update_id => $update_id,
        service_request_id => $row->{CRNo}+0,
        description => '', # lca description not used
        updated_datetime => $dt,
    );
}

1;
