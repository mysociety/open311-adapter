package Open311::Endpoint::Integration::SalesForceRest;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';

use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::UKCouncil::Salesforce;

use Integrations::SalesForceRest;

use DateTime::Format::Strptime;
use Types::Standard ':all';

sub service_request_content {
    '/open311/service_request_extended'
}

has jurisdiction_id => ( is => 'ro' );

has '+identifier_types' => (
    is => 'lazy',
    isa => HashRef[Any],
    default => sub {
        my $self = shift;
        return {
            # type names can have all sorts in them
            service_code => { type => '/open311/regex', pattern => qr/^ [\w_\- \/\(\),&;]+ $/ax },
        };
    },
);

has blacklist => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my %blacklist = map { $_ => 1 } @{ $self->get_integration->config->{service_blacklist} };
        return \%blacklist;
    }
);

has whitelist => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my %whitelist = map { $_ => 1 } @{ $self->get_integration->config->{service_whitelist} };
        return \%whitelist;
    }
);

sub integration_class { 'Integrations::SalesForceRest' }

sub get_integration {
    my $self = shift;
    return $self->integration_class->new(config_filename => $self->jurisdiction_id);
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    my $new_id = $self->integration->post_request($service, $args);

    my $request = $self->new_request(
        service_request_id => $new_id,
    );

    return $request;
}

sub services {
    my ($self, $args) = @_;

    my @services = $self->get_integration->get_services($args);

    my @service_types;
    for my $service ( @services ) {
        next unless scalar @{ $service->{groups} };

        next unless grep { $self->whitelist->{$_} } @{ $service->{groups} };

        next if $self->blacklist->{$service->{value}};

        my $service = Open311::Endpoint::Service::UKCouncil::Salesforce->new(
            service_name => $service->{label},
            description => $service->{label},
            service_code => $service->{value},
            groups => $service->{groups},
        );

        push @service_types, $service;
    }

    return @service_types;
}

sub service {
    my ($self, $id, $args) = @_;

    my $meta = $self->get_integration->get_service($id, $args);

    my $service = Open311::Endpoint::Service::UKCouncil::Salesforce->new(
        service_name => $meta->{label},
        description => $meta->{label},
        service_code => $meta->{value},
        groups => $meta->{groups},
    );

    return $service;
}

__PACKAGE__->run_if_script;
