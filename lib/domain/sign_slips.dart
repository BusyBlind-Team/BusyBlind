/// 签文池（文字由橡皮擦负责，v0.1 先放占位文案；每日一次，抽到即收藏）。
class SignSlip {
  const SignSlip({required this.id, required this.text, required this.fortune});

  final String id;
  final String text;
  final String fortune;
}

const List<SignSlip> kSignSlips = [
  SignSlip(id: 's1', text: '风来竹面，雁过潭心。不追不赶，自有所得。', fortune: '上签'),
  SignSlip(id: 's2', text: '忙里偷得半炷香，闭眼即见旧时山。', fortune: '上签'),
  SignSlip(id: 's3', text: '水急不流月，心急不成事。慢即是快。', fortune: '中签'),
  SignSlip(id: 's4', text: '今日宜少看屏幕，宜早睡一刻钟。', fortune: '中签'),
  SignSlip(id: 's5', text: '雨会停，会也会来。等一等，不丢人。', fortune: '中签'),
  SignSlip(id: 's6', text: '手里事多如落叶，先拾眼前这一片。', fortune: '中签'),
  SignSlip(id: 's7', text: '久立无风处，回身自有门。', fortune: '下签'),
  SignSlip(id: 's8', text: '今日话多必失，不如多听三分钟。', fortune: '下签'),
];
