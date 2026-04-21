use Test::More 'no_plan';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";

use List::Util 'uniq';
use Gitprep::Repository;

my @cases = (
  {
    stimulus => {
      class       => 'Gitprep::Repository',
      user        => 'user1',
      project     => 'project1',
      classhome   => '/bare_home'
    },
    expected => {
      home        => '/bare_home',
      user        => 'user1',
      project     => 'project1',
      root        => '/bare_home/user1/project1.git',
      git_dir     => '/bare_home/user1/project1.git',
      url         => '/user1/project1',
      remote_name => 'repo/user1/project1',
      is_wiki     => 0
    }
  },
  {
    stimulus => {
      class       => 'Gitprep::Repository::Work',
      user        => 'yuki-kimoto',
      project     => 'SPVM',
      classhome   => '/work_home'
    },
    expected => {
      home        => '/work_home',
      user        => 'yuki-kimoto',
      project     => 'SPVM',
      root        => '/work_home/yuki-kimoto/SPVM',
      git_dir     => '/work_home/yuki-kimoto/SPVM/.git',
      work_tree   => '/work_home/yuki-kimoto/SPVM',
      is_wiki     => 0
    }
  },
  {
    stimulus => {
      class       => 'Gitprep::Repository::Work',
      user        => 'Linus',
      project     => 'kernel',
      home        => '/tempdir'
    },
    expected => {
      home        => '/tempdir',
      user        => 'Linus',
      project     => 'kernel',
      root        => '/tempdir/Linus/kernel',
      git_dir     => '/tempdir/Linus/kernel/.git',
      work_tree   => '/tempdir/Linus/kernel',
      is_wiki     => 0
    }
  },
  {
    stimulus => {
      class       => 'Gitprep::Repository::Wiki',
      user        => 'u',
      project     => 'p',
    },
    expected => {
      home        => '/bare_home',
      user        => 'u',
      project     => 'p',
      root        => '/bare_home/u/p.wiki.git',
      git_dir     => '/bare_home/u/p.wiki.git',
      url         => '/u/p/wiki',
      remote_name => 'repo/u/p.wiki',
      is_wiki     => 1
    }
  },
  {
    stimulus => {
      class       => 'Gitprep::Repository::Wiki',
      user        => 'pm',
      project     => 'gitprep',
      is_work     => 1
    },
    expected => {
      home        => '/work_home',
      user        => 'pm',
      project     => 'gitprep',
      root        => '/work_home/pm/gitprep.wiki',
      git_dir     => '/work_home/pm/gitprep.wiki/.git',
      work_tree   => '/work_home/pm/gitprep.wiki',
      is_wiki     => 1
    }
  }
);

for (@cases) {
  my $stimulus = $_->{stimulus};
  my $expected = $_->{expected};
  $stimulus->{class}->home($stimulus->{classhome}, $stimulus->{is_work})
    if defined $stimulus->{classhome};
  my $rep_info = $stimulus->{class}->new($stimulus->{user},
    $stimulus->{project}, $stimulus->{is_work});
  $rep_info = $rep_info->work if $stimulus->{is_work};
  $rep_info->home($stimulus->{home}) if defined $stimulus->{home};
  my %result;
  for my $method ('home', 'user', 'project', 'root', 'git_dir',
    'url', 'work_tree', 'remote_name', 'is_wiki') {
   $result{$method} = $rep_info->$method if $rep_info->can($method);
  }
  for my $method (sort(uniq(keys(%result), keys(%$expected)))) {
    my $is_work = $stimulus->{is_work}? '(work)': '';
    is ($result{$method}, $expected->{$method},
      "$stimulus->{class}$is_work $stimulus->{project}: $method");
  }
}
