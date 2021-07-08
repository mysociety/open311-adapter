package Open311::Endpoint::Integration::UK::Bexley::Symology;

# use SOAP::Lite +trace => [ qw/method debug/ ];

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

use Open311::Endpoint::Service::UKCouncil::BexleySymology;

has jurisdiction_id => (
    is => 'ro',
    default => 'bexley_symology',
);

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::BexleySymology'
);

sub process_service_request_args {
    my $self = shift;
    my @args = $self->SUPER::process_service_request_args(@_);
    my $request = $args[0];

    my $lookup = $self->endpoint_config->{nsgref_to_action};
    $request->{NextAction} = $lookup->{$request->{NSGRef} || ''} || 'S6';

    return @args;
}

sub event_action_event_type {
    my ($self, $args) = @_;
    return do {
          $args->{ServiceCode} eq 'SLC' && $args->{closed} ? 'RC'
        : $args->{closed} ? 'CR'
        : 'CCA'
    };
}

sub _row_status {
    my ($self, $row) = @_;

    return do {
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
        } elsif ($action_due =~ /^IR|REH|RES|RET|RP|RPOS|RT|RWT$/) {
            'internal_referral'
        } elsif ($action_due eq 'NCR') {
            'not_councils_responsibility'
        } elsif ($action_due =~ /^([NS]I[1-6]MOB|IPSGM|IGF|IABV)$/) {
            'investigating'
        } elsif ($action_due =~ /^PT[CS]|TPHR|REIN$/) {
            'action_scheduled'
        } elsif ($row->{Stage} == 9) {
            undef
        } else {
            'open' # XXX Might want to maintain existing status?
        }
    };
}

sub _row_external_status_code {
    my ($self, $row, $status) = @_;
    return undef unless $status && ( $status eq 'not_councils_responsibility'
                        || $status eq 'action_scheduled'
                        || $status eq 'internal_referral' );
    return $row->{'Event Type'};
}

sub _row_description { '' } # lca description not used

1;
