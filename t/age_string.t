#!/usr/bin/env perl

use Test::More;

use Gitprep::Git;

my @cases = (
  { stimulus =>                       0,     expected => ' right now'    },
  { stimulus =>                       1,     expected => 'a sec ago'     },
  { stimulus =>                      59,     expected => '59 sec ago'    },
  { stimulus =>                      60,     expected => 'a min ago'     },
  { stimulus =>                      60 + 1, expected => 'a min ago'     },
  { stimulus =>                  2 * 60 - 1, expected => 'a min ago'     },
  { stimulus =>                  2 * 60,     expected => '2 min ago'     },
  { stimulus =>                  2 * 60 + 1, expected => '2 min ago'     },
  { stimulus =>                 60 * 60 - 1, expected => '59 min ago'    },
  { stimulus =>                 60 * 60,     expected => 'a hours ago'   },
  { stimulus =>                 60 * 60 + 1, expected => 'a hours ago'   },
  { stimulus =>                 61 * 60,     expected => 'a hours ago'   },
  { stimulus =>            24 * 60 * 60 - 1, expected => '23 hours ago'  },
  { stimulus =>            24 * 60 * 60,     expected => 'a days ago'    },
  { stimulus =>            24 * 60 * 60 + 1, expected => 'a days ago'    },
  { stimulus =>        7 * 24 * 60 * 60 - 1, expected => '6 days ago'    },
  { stimulus =>        7 * 24 * 60 * 60,     expected => 'a weeks ago'   },
  { stimulus =>        7 * 24 * 60 * 60 + 1, expected => 'a weeks ago'   },
  { stimulus => (365/12) * 24 * 60 * 60 - 1, expected => '4 weeks ago'   },
  { stimulus => (365/12) * 24 * 60 * 60,     expected => 'a months ago'  },
  { stimulus => (365/12) * 24 * 60 * 60 + 1, expected => 'a months ago'  },
  { stimulus =>  365     * 24 * 60 * 60 - 1, expected => '11 months ago' },
  { stimulus =>  365     * 24 * 60 * 60,     expected => 'a years ago'   },
  { stimulus =>  365     * 24 * 60 * 60 + 1, expected => 'a years ago'   },
);

plan ( tests => scalar @cases );

for ( @cases ) {
  is ( Gitprep::Git->_age_string ( $_->{stimulus} ), $_->{expected}, "$_->{stimulus} sec ~ \"$_->{expected}\"" );
}
