AWS_ACCESS_KEY_ID ='AKIAJWUX7FTA4K5RSLRQ'
AWS_SECRET_ACCESS_KEY = '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'


$req = Vacuum.new
$req.configure(
    aws_access_key_id: AWS_ACCESS_KEY_ID,
    aws_secret_access_key: AWS_SECRET_ACCESS_KEY,
    associate_tag: 'tag'
)