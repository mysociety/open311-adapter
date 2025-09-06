package Integrations::Confirm::DummyPhotos;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("confirm_photos.yml")->stringify }

package Open311::Endpoint::Integration::UK::DummyPhotos;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_dummy_photos';
    $args{config_file} = path(__FILE__)->sibling("confirm_photos.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::DummyPhotos');

package main;

use strict;
use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;

use JSON::MaybeXS;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

my $lwp = Test::MockModule->new('LWP::UserAgent');
sub empty_json { HTTP::Response->new(200, 'OK', [], '{}') }
$lwp->mock(request => \&empty_json);

my $integration = Test::MockModule->new('Integrations::Confirm');
$integration->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    $op = $op->value;
    if ($op->name && $op->name eq 'GetEnquiryStatusChanges') {
          return {
              OperationResponse => {
                  GetEnquiryStatusChangesResponse => {
                      UpdatedEnquiry => [
                          {
                              EnquiryNumber => 2020,
                              EnquiryStatusLog => [
                                  {
                                      EnquiryLogNumber => 2,
                                      StatusLogNotes => 'status log notes',
                                      LogEffectiveTime => '2025-01-01T00:00:00Z',
                                      LoggedTime => '2025-01-01T00:00:00Z',
                                      EnquiryStatusCode => 'FIX'
                                  }
                              ]
                          }
                      ]
                  }
              }
          }
      }
      return {};
});


my $endpoint = Open311::Endpoint::Integration::UK::DummyPhotos->new;

subtest "fetching of job photos for enquiry update" => sub {
    my $lwp = Test::MockModule->new('LWP::UserAgent');
    $lwp->mock(request => sub {
        my ($ua, $req) = @_;
        return HTTP::Response->new(200, 'OK', [], '{"access_token":"123","expires_in":3600}') if $req->uri =~ /oauth\/token/;
        return HTTP::Response->new(200, 'OK', [], '{"jobNumber":"432"}') if $req->uri =~ /enquiries\/2020/;
        return HTTP::Response->new(200, 'OK', [], '{"documents":[
            {"documentNo":1,"fileName":"photo1.jpeg","documentNotes":"Before"},
            {"documentNo":2,"fileName":"photo2.jpeg","documentNotes":"After"}
            ]}') if $req->uri =~ /jobs\/432/;
    });
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2025-01-01T00:00:00Z&end_date=2025-01-01T01:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<media_url>http://example.com/photo/completion?jurisdiction_id=confirm_dummy_photos&amp;job=432&amp;photo=1</media_url>';
    $lwp->mock(request => \&empty_json);
};

done_testing;
