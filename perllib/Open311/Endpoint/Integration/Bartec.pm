package Open311::Endpoint::Integration::Bartec;

use JSON::MaybeXS;
use Path::Tiny;
use YAML::XS qw(LoadFile);

use Integrations::Bartec;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::Logger';

use Open311::Endpoint::Service::UKCouncil::Bartec;

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
    $services = ref $services->{ServiceType} eq 'ARRAY' ? $services->{ServiceType} : [ $services->{ServiceType} ];
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

    my $premises = $integ->Premises_Get(
        $args->{attributes}->{site_code}, $args->{attributes}->{postcode}, $args->{attributes}->{house_no}, $args->{attributes}->{street}
    );
    if ($premises) {
        my $result = ref $premises->{Premises} eq 'ARRAY' ? $premises->{Premises}->[0] : $premises->{Premises};
        $args->{uprn} = $result->{UPRN};
    }
    my $defaults = $config->{field_defaults} || {};
    my $req = {
        %$defaults,
        %$args
    };

    my $res = $integ->ServiceRequests_Create($service, $req);
    die "failed to send" unless $res->{ServiceCode};
    return $self->new_request(
        service_request_id => $res->{ServiceCode}
    );


}

__PACKAGE__->run_if_script;
