package Open311::Endpoint::Role::BexleyPrivateComments;

use Moo::Role;

sub private_comments_attribute {
  Open311::Endpoint::Service::Attribute->new(
      code => "private_comments",
      description => "Private comments",
      datatype => "string",
      required => 0,
      automated => 'server_set',
  )
}

1;
