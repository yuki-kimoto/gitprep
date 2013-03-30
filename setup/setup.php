<?php
  $current_url = 'http://' . $_SERVER["SERVER_NAME"] . $_SERVER["SCRIPT_NAME"];
  $output = array('');
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
    <div class="container">
      <div class="text-center"><h1>Setup Tool</h1></div>
    </div>
    <hr style="margin-top:0;margin-bottom:0">
    <div class="container">
      <div class="text-center"><b><h3>Click!</h3></b></div>
      <form action="<?php echo "$current_url?op=setup" ?>" method="post">
        <div class="text-center" style="margin-bottom:10px">
          <input type="submit" style="width:200px;height:50px;font-size:200%" value="Setup">
        </div>
      </form>
      <span class="label">Result</span>
      <pre style="height:300px">
        <?php if ($output) { ?>
          <?php foreach ($output as $line) { ?>
            <?php echo $line ?>
          <?php } ?>
        <?php } ?>
      </pre>
    </div>
  </body>
</html>
