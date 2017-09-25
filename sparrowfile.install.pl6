
if target_os() ~~ /alpine/ {
  user 'gitprep'
}

task-run "install gitprep server", "gitprep";

package-install "git";


bash "cd ~/gitprep && ./gitprep", %(
  user => "gitprep",
  description => "run gitprep server"
);

http-ok %( port => 10020 );
