package Open311::Endpoint::Integration::UK::Hackney::Environment;

use Moo;
extends 'Open311::Endpoint::Integration::UK::Hackney::Base';

use Open311::Endpoint::Service::UKCouncil::Alloy::HackneyEnvironment;

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Alloy::HackneyEnvironment'
);

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'hackney_environment_alloy_v2';
    return $class->$orig(%args);
};

1;
