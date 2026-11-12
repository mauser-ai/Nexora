<?php
require __DIR__ . '/../../backend/api/teamleader/mapper.php';
function check($value, $expected): void {
    if ($value !== $expected) throw new RuntimeException('Mapping non valido: '.json_encode([$value,$expected]));
}
check(tls_map('companies',['name'=>'Acme','emails'=>[['email'=>'test@example.com']]]),['name'=>'Acme','email'=>'test@example.com']);
check(tls_map('companies',['name'=>'Acme']),['name'=>'Acme']);
check(tls_map('companies',['emails'=>[]]),['email'=>'']);
check(tls_map('deals',['status'=>'won','estimated_value'=>['amount'=>120]]),['value'=>120,'status'=>'won']);
$r=tls_map('timetracking',['started_on'=>'2026-11-10','started_at'=>'2026-11-10T10:00:00+01:00','duration'=>1800,'subject'=>['type'=>'todo','id'=>'x']]);
check($r['start_at'],'2026-11-10 10:00:00');
check($r['end_at'],'2026-11-10 10:30:00');
check($r['task_id'],'x');
check(isset($r['notes']),false);
$real=tls_map('timetracking',['started_on'=>'2026-11-10','started_at'=>'2026-11-10T13:50:00+01:00','ended_at'=>'2026-11-10T14:10:00+01:00','duration'=>1200,'invoiceable'=>false,'subject'=>['type'=>'company','id'=>'c']]);
check($real['start_at'],'2026-11-10 13:50:00');check($real['end_at'],'2026-11-10 14:10:00');check($real['billable'],0);check($real['task_id'],'');
$only=tls_map('timetracking',['started_on'=>'2026-11-10','started_at'=>null,'ended_at'=>null,'duration'=>1200]);
check($only['start_at'],'2026-11-10 00:00:00');check($only['tipo'],'teamleader_duration');
$summer=tls_map('timetracking',['started_on'=>'2026-07-01','started_at'=>'2026-06-30T22:30:00Z','duration'=>1800]);
check($summer['start_at'],'2026-07-01 00:30:00');
date_default_timezone_set('Europe/Rome');
check(tls_map('projects',['starts_on'=>'2026-11-10'])['data_inizio_progetto'],'2026-11-10');
$parents=['work_tasks'=>['name'=>'Task','phase_id'=>'phase','project_id'=>'project','company_id'=>''], 'project_phases'=>['project_id'=>'project'], 'projects'=>['company_id'=>'company'],'companies'=>[]];
$links=tls_inherit_links(['task_id'=>'task','project_id'=>'','company_id'=>'','name'=>''],[],static function($table,$id) use($parents){return $parents[$table];});
check($links['project_id'],'project');check($links['company_id'],'company');check($links['name'],'Task');
$changed=tls_map('timetracking',['started_on'=>'2026-11-10','duration'=>1200,'subject'=>['type'=>'company','id'=>'c']]);
check($changed['task_id'],'');check($changed['project_id'],'');
check(tls_map('quotations',['name'=>'112'])['number'],'112');
check(array_key_exists('lines',tls_map('quotations',['name'=>'112'])),false);
check(tls_map('phases',['status'=>'closed'])['status'],'done');
check(tls_map('projects',['status'=>'open','customers'=>[['id'=>'company-1','type'=>'company']]])['company_id'],'company-1');
try {
    tls_map('projects',['customers'=>[['id'=>'a'],['id'=>'b']]]);
    throw new RuntimeException('Progetto multi-cliente non sospeso');
} catch (InvalidArgumentException $e) {}
echo "Mapper tests passed\n";
