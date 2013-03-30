<?php
  # Config
  $setup_dir = getcwd();
  $app_home_dir = $setup_dir . '/..';
  $cpanm_path = "$app_home_dir/cpanm";
  putenv("PERL_CPANM_HOME=$setup_dir");
  
  # Paramter
  $op = $_REQUEST['op'];
  
  $current_path = $_SERVER["SCRIPT_NAME"];
  $output = array('');
  $app_home_dir = getcwd() . '/..';
  $success = true;
  
  if($op == 'setup') {
    
    if (!chdir($app_home_dir)) {
      throw new Exception("Can't cahgne directory");
    }
    exec("perl cpanm -n -l extlib Module::CoreList 2>&1", $output, $ret);
    
    if ($ret == 0) {
      exec("perl -Iextlib/lib/perl5 cpanm -n -L extlib --installdeps . 2>&1", $output, $ret);
      if ($ret == 0) {
        $success = true;
      }
      else {
        $success = false;
      }
    }
    else {
      $success = false;
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
    <?php echo $cpanm_path ?>
    
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
      <span class="label">Result</span>
<pre style="height:300px;overflow:auto;margin-bottom:0;margin-top:0;">
<?php if (!$success) { ?>
<span style="color:red">Error</span>
<?php } ?>
<?php if ($output) { ?>
<?php foreach ($output as $line) { ?>
<?php echo htmlspecialchars($line) ?>

<?php } ?>
<?php } ?>
</pre>
    </div>
  </body>
</html>
