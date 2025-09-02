public class AWSS3MockCallout implements HttpCalloutMock {
    public static String lastMethod;
    public static String lastEndpoint;

    public HttpResponse respond(HttpRequest req) {
        lastMethod = req.getMethod();
        lastEndpoint = req.getEndpoint();

        HttpResponse res = new HttpResponse();

        if (req.getMethod() == 'GET' && req.getEndpoint().contains('?prefix=')) {
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/xml');
            res.setBody(
                '<ListBucketResult>' +
                    '<Contents>' +
                        '<Key>Account/001abc/test1.jpg</Key>' +
                        '<LastModified>2025-08-01T12:00:00.000Z</LastModified>' +
                        '<ETag>"etag-123"</ETag>' +
                        '<Size>1024</Size>' +
                        '<StorageClass>STANDARD</StorageClass>' +
                    '</Contents>' +
                    '<Contents>' +
                        '<Key>Account/001abc/test2.jpg</Key>' +
                        '<LastModified>2025-08-02T12:00:00.000Z</LastModified>' +
                        '<ETag>"etag-456"</ETag>' +
                        '<Size>2048</Size>' +
                        '<StorageClass>STANDARD</StorageClass>' +
                    '</Contents>' +
                '</ListBucketResult>'
            );
        } else if (req.getMethod() == 'DELETE') {
            res.setStatusCode(204); // No Content
        } 

        return res;
    }
}