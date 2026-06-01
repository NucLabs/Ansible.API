$ret = Start-AAPJobTemplate -Name 'Get Ad User' -Wait
$result = Get-AAPJobEvents -Id $ret.id
$result[9].event_data.res.'ad_user_result.output' 
