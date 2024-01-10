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

    $request->{NextAction} = $self->post_add_next_action_update($request->{NSGRef});

    return @args;
}

sub post_add_next_action_update {
    my $self = shift;
    my $nsg = shift;

    my $lookup = $self->endpoint_config->{nsgref_to_action};

    return $lookup->{$nsg || ''} || 'S6';
}

sub event_action_event_type {
    my ($self, $args) = @_;
    return do {
          $args->{ServiceCode} eq 'SLC' && $args->{closed} ? 'RC'
        : $args->{closed} ? 'CR'
        : 'CCA'
    };
}

sub _update_status {
    my ($self, $row) = @_;

    my $status = do {
        my $street_cleansing = exists $row->{'Maint.Recd.'};
        my $maint_stage = $row->{'Maint. Stage'} || '';
        my $action_due = $row->{'Action Due'} || '';
        if ($street_cleansing) {
            if ($maint_stage eq 'ORDERED') {
                'action_scheduled'
            } elsif ($maint_stage =~ /COMPLETED|APPROVED/) {
                'fixed'
            } else {
                undef
            }
        } elsif ($maint_stage eq 'ORDERED') {
            'investigating'
        } elsif ($maint_stage eq 'COMMENCED' || $maint_stage eq 'ALLOCATED') {
            'action_scheduled'
        } elsif ($maint_stage =~ /COMPLETED|CLAIMED|APPROVED/) {
            'fixed'
        } elsif ($action_due =~ /^(CLEARREQ|NRSM|NF|NDMC|NTBR|NFA)$/) {
            'no_further_action'
        } elsif ($action_due =~ /^(CR|NR)$/) {
            'fixed'
        } elsif ($action_due =~ /^([NS][1-6]|RPOS)$/) {
            'in_progress'
        } elsif ($action_due =~ /^(IR|RBC|REH|RES|RET|RP|RPL|RSW|RT|RWT)$/) {
            'internal_referral'
        } elsif ($action_due eq 'NCR') {
            'not_councils_responsibility'
        } elsif ($action_due =~ /^([NS]I[1-6]MOB|IPSGM|IGF|IABV)$/) {
            'investigating'
        } elsif ($action_due =~ /^PT[CS]|TPHR|REIN$/) {
            'action_scheduled'
        } elsif ($action_due eq 'ROD') {
            'closed'
        } elsif ($row->{Stage} == 9 || $row->{Stage} == 8) {
            undef
        } else {
            'open' # XXX Might want to maintain existing status?
        }
    };

    my $esc = do {
        if ($status && ( $status eq 'not_councils_responsibility'
                        || $status eq 'action_scheduled'
                        || $status eq 'closed'
                        || $status eq 'internal_referral' )) {
            $row->{'Event Type'};
        } else {
            undef
        }
    };

    return ($status, $esc);
}

sub _update_description { '' } # lca description not used

1;
