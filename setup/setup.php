<?php
  # Config
  $setup_dir = getcwd();
  $script_dir = realpath($setup_dir . '/../script');
  $app_home_dir = realpath($setup_dir . '/..');
  $cpanm_path = "$app_home_dir/cpanm";
  putenv("PERL_CPANM_HOME=$setup_dir");
  
  # Paramter
  $op = $_REQUEST['op'];
  
  $current_path = $_SERVER["SCRIPT_NAME"];
  $app_path = $current_path;
  $app_path = preg_replace('/\/setup\/setup\.php/', '', $app_path) . '.cgi';
  preg_match("/([0-9a-zA-Z-_]+\.cgi)$/", $app_path, $matches);
  $script_base_name = $matches[0];
  $script = "$script_dir/$script_base_name";
  $to_script = realpath("$app_home_dir/../$script_base_name");
  $output = array('');
  $app_home_dir = getcwd() . '/..';
  $setup_command_success = true;
  
  if($op == 'setup') {
    
    if (!chdir($app_home_dir)) {
      throw new Exception("Can't cahgne directory");
    }
    exec("perl cpanm -n -l extlib Module::CoreList 2>&1", $output, $ret);
    
    $output = array();
    if ($ret == 0) {
      exec("perl -Iextlib/lib/perl5 cpanm -n -L extlib --installdeps . 2>&1", $output, $ret);
      if ($ret == 0) {
        if (copy($script, $to_script)) {
          array_push($output, "$script is moved to $to_script");
          if (chmod($to_script, 0755)) {
            array_push($output, "change $to_script mode to 755");
            $setup_command_success = true;
          }
          else {
            array_push($output, "Can't change mode $to_script");
            $setup_command_success = false;
          }
        }
        else {
          array_push($output, "Can't move $script to $to_script");
          $setup_command_success = false;
        }
      }
      else {
        $setup_command_success = false;
      }
    }
    else {
      $setup_command_success = false;
    }
  }
?>

<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <title>Setup Tool</title>
    <script src="js/jquery-1.9.0.min.js"></script>
    <script src="js/bootstrap.js"></script>
    <link rel="stylesheet" href="css/bootstrap.css" />
    <link rel="stylesheet" href="css/bootstrap-responsive.css" />
  </head>
  <body>
    <?php echo $script ?>
    <div class="container">
      <div class="text-center"><h1>Setup Tool</h1></div>
    </div>
    <hr style="margin-top:0;margin-bottom:0">
    <div class="container">
      <div class="text-center"><b><h3>Click!</h3></b></div>
      <form action="<?php echo "$current_path?op=setup" ?>" method="post">
        <div class="text-center" style="margin-bottom:10px">
          <input type="submit" style="width:200px;height:50px;font-size:200%" value="Setup">
        </div>
      </form>

<?php if ($op == 'setup') { ?>
      <span class="label">Result</span>
<pre style="height:300px;overflow:auto;margin-bottom:30px">
<?php if (!$setup_command_success) { ?>
<span style="color:red">Error, Setup failed.</span>
<?php } ?>
<?php if ($setup_command_success) { ?>
<?php foreach ($output as $line) { ?>
<?php echo htmlspecialchars($line) ?>

<?php } ?>
<?php } ?>
</pre>
<?php } ?>

      <?php if ($op == 'setup' && $setup_command_success) { ?>
        <div style="font-size:150%;margin-bottom:30px;">Go to <a href="<?php echo $app_path ?>">Application</a></div>
      <?php } ?>
    </div>
  </body>
</html>
