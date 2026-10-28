# cloudfront-origin

A private origin read only by one CloudFront distribution through Origin
Access Control, with ACLs disabled as OAC requires. Old versions expire
after 30 days, since every deploy overwrites the content. SSE-S3 keeps
CloudFront out of a key policy; with a customer key, the key contract would
include it.
