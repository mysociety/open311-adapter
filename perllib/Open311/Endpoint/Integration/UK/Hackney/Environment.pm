package Open311::Endpoint::Integration::UK::Hackney::Environment;

use Moo;
extends 'Open311::Endpoint::Integration::UK::Hackney::Base';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'hackney_environment_alloy_v2';
    return $class->$orig(%args);
};

sub defect_status {
    my ($self, $status, $defect) = @_;

    my $return_status;

    my $reason_mapping = $self->config->{cancellation_reason_mapping};
    my $task_mapping = $self->config->{task_status_mapping};
    my $task_status = $defect->{$self->config->{defect_attribute_mapping}->{task_status}};
    my $reason = $defect->{$self->config->{defect_attribute_mapping}->{cancellation_reason}};
    if ( $task_status && $reason ) {
        $task_status = $task_status->[0] if ref $task_status eq 'ARRAY';
        $reason = $reason->[0] if ref $reason eq 'ARRAY';

        $return_status = $reason_mapping->{$reason} if $task_mapping->{$task_status} eq 'Cancelled';
    }

    unless ( $return_status ) {
        $status = $status->[0] if ref $status eq 'ARRAY';
        $return_status = $self->config->{defect_status_mapping}->{$status} || 'open';
    }

    return $return_status;
}


1;
