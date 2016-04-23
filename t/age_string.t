use Test::More 'no_plan';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";

use Gitprep::Git;

my @cases = (
  { stimulus =>                           0,     expected => 'right now'     },
  { stimulus =>                           1,     expected => 'a sec ago'     },
  { stimulus =>                          59,     expected => '59 sec ago'    },
  { stimulus =>                          60,     expected => 'a min ago'     },
  { stimulus =>                          60 + 1, expected => 'a min ago'     },
  { stimulus =>                      2 * 60 - 1, expected => 'a min ago'     },
  { stimulus =>                      2 * 60,     expected => '2 min ago'     },
  { stimulus =>                      2 * 60 + 1, expected => '2 min ago'     },
  { stimulus =>                     60 * 60 - 1, expected => '59 min ago'    },
  { stimulus =>                     60 * 60,     expected => 'an hour ago'   },
  { stimulus =>                     60 * 60 + 1, expected => 'an hour ago'   },
  { stimulus =>                     61 * 60,     expected => 'an hour ago'   },
  { stimulus =>                24 * 60 * 60 - 1, expected => '23 hours ago'  },
  { stimulus =>                24 * 60 * 60,     expected => 'a day ago'     },
  { stimulus =>                24 * 60 * 60 + 1, expected => 'a day ago'     },
  { stimulus =>            7 * 24 * 60 * 60 - 1, expected => '6 days ago'    },
  { stimulus =>            7 * 24 * 60 * 60,     expected => 'a week ago'    },
  { stimulus =>            7 * 24 * 60 * 60 + 1, expected => 'a week ago'    },
  { stimulus =>     (365/12) * 24 * 60 * 60 - 1, expected => '4 weeks ago'   },
  { stimulus =>     (365/12) * 24 * 60 * 60,     expected => 'a month ago'   },
  { stimulus =>     (365/12) * 24 * 60 * 60 + 1, expected => 'a month ago'   },
  { stimulus =>      365     * 24 * 60 * 60 - 1, expected => '11 months ago' },
  { stimulus =>      365     * 24 * 60 * 60,     expected => 'a year ago'    },
  { stimulus =>      365     * 24 * 60 * 60 + 1, expected => 'a year ago'    },
  { stimulus =>  2 * 365     * 24 * 60 * 60 - 1, expected => 'a year ago'    },
  { stimulus =>  2 * 365     * 24 * 60 * 60,     expected => '2 years ago'   },
  { stimulus =>  2 * 365     * 24 * 60 * 60 + 1, expected => '2 years ago'   },
);

for ( @cases ) {
  is ( Gitprep::Git->new->_age_string ( $_->{stimulus} ), $_->{expected}, "$_->{stimulus} sec ~ \"$_->{expected}\"" );
}
