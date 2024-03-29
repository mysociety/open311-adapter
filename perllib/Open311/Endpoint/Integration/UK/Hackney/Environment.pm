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

sub defect_status {
    my ($self, $defect) = @_;

    my $return_status;

    my $reason_mapping = $self->config->{cancellation_reason_mapping};
    my $task_mapping = $self->config->{task_status_mapping};
    my $task_status = $defect->{$self->config->{defect_attribute_mapping}->{task_status}};
    my $reason = $defect->{$self->config->{defect_attribute_mapping}->{cancellation_reason}};
    if ( $task_status && $reason ) {
        $task_status = $task_status->[0] if ref $task_status eq 'ARRAY';
        $reason = $reason->[0] if ref $reason eq 'ARRAY';

        return $reason_mapping->{$reason} if $task_mapping->{$task_status} eq 'Cancelled';
    }

    return $self->SUPER::defect_status($defect);
}


1;
