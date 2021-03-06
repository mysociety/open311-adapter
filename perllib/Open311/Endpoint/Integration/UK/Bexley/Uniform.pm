package Open311::Endpoint::Integration::UK::Bexley::Uniform;

use Moo;
extends 'Open311::Endpoint::Integration::Uniform';

use Open311::Endpoint::Service::UKCouncil::BexleyUniform;

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::BexleyUniform'
);

has jurisdiction_id => (
    is => 'ro',
    default => 'bexley_uniform',
);

sub web_service {
    my ($self, $service) = @_;

    if ($service->service_code eq 'DFOUL') {
        return 'SubmitDogServiceRequest';
    } else {
        return 'SubmitGeneralServiceRequest';
    }
}

my %closing_action_codes = (
    RESFIX => 'fixed',
    DUPR => 'duplicate',
    REFER => 'internal_referral',
    REFERE => 'not_councils_responsibility',
    NFA => 'no_further_action',
    NAP => 'no_further_action',
);

sub map_status_code {
    my ($self, $status_code, $closing_code) = @_;

    my $status;
    if ($status_code eq '8_CLO') {
        $status = $closing_action_codes{$closing_code} || 'fixed';
    } elsif ($status_code eq '4_INV') {
        $status = 'investigating';
    }
    return $status;
}

1;
