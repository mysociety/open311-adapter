package Open311::Endpoint::Integration::Symology;

use v5.14;
use warnings;

use Moo;
use Path::Tiny;
use JSON::MaybeXS;
use YAML::XS qw(LoadFile);
use YAML::Logic;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::Logger';

use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::Update::mySociety;
use Open311::Endpoint::Service::UKCouncil::Symology;

has jurisdiction_id => ( is => 'ro' );

has endpoint_config => ( is => 'lazy' );

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

sub get_integration {
    my $self = shift;
    return $self->integration_class->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->faultstring : $soap->transport->status, "\n"; });
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

    $self->check_error($response, 'Request');

    my $result = $response->{SendRequestResults}->{SendRequestResultRow};
    my $request = $self->new_request(
        service_request_id => $result->{ConvertCRNo},
    );

    return $request;
}

sub process_service_request_update_args {
    my ($self, $args) = @_;

    my $service_code = $args->{service_code};
    my $codes = $self->category_mapping->{$service_code};
    $self->log_and_die("Could not find category mapping for $service_code") unless $codes;

    my $request = {
        Description => $args->{description},
        ServiceCode => $codes->{parameters}{ServiceCode},
        CRNo => $args->{service_request_id},
        fixmystreet_id => $args->{service_request_id_ext},
        UserName => $self->username,
    };

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

    $self->check_error($response, 'Action');

    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => lc $args->{status},
        update_id => $args->{update_id},
    );
}

sub check_error {
    my ($self, $response, $type) = @_;

    $self->log_and_die("Couldn't create $type in Symology") unless defined $response;

    $self->logger->debug(encode_json($response));

    unless (($response->{StatusCode}//-1) == 0) {
        my $error = "Couldn't create $type in Symology: $response->{StatusMessage}";
        my $result = $response->{SendRequestResults}->{SendRequestResultRow};
        $result = [ $result ] if ref $result ne 'ARRAY';
        foreach (@$result) {
            $error .= " - $_->{MessageText}" if $_->{RecordType} == 1;
            $error .= " - created request $_->{ConvertCRNo}" if $_->{RecordType} == 2;
        }
        $self->log_and_die($error);
    }
}

sub get_service_request_updates {
    my ($self, $args) = @_;
    # TODO
    return ();
}

1;
