from __future__ import print_function

import argparse
import json
import os
import sys
import time
import traceback
import ssl
import urllib3
from threading import Thread
from concurrent import futures

import gunicorn.app.base
from flask import Flask, Response, json, make_response, request
import prometheus_client
from prometheus_client import CollectorRegistry, Summary, multiprocess, Histogram, Counter

from ExternalServiceExecutor import init_REST, init_gRPC, run_external_service
from InternalServiceExecutor import run_internal_service

import mub_pb2_grpc as pb2_grpc
import mub_pb2 as pb2
import grpc


# Configuration of global variables
jaeger_headers_list = [
    'x-request-id',
    'x-b3-traceid',
    'x-b3-spanid',
    'x-b3-parentspanid',
    'x-b3-sampled',
    'x-b3-flags',
    'x-datadog-trace-id',
    'x-datadog-parent-id',
    'x-datadog-sampling-priority',
    'x-ot-span-context',
    'grpc-trace-bin',
    'traceparent',
    'x-cloud-trace-context',
]

# Flask APP
app = Flask(__name__)
ID = os.environ["APP"]
ZONE = os.environ["ZONE"]
K8S_APP = os.environ["K8S_APP"]
PN = os.environ["PN"]
TN = os.environ["TN"]
COMM_PROTOCOL = os.environ.get("COMM_PROTOCOL", "http")  # http or https
traceEscapeString = "__"

# Disable SSL warnings when using self-signed certificates
if COMM_PROTOCOL == "https":
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

globalDict = dict()

def read_config_files():
    res = dict()
    with open('MSConfig/workmodel.json') as f:
        workmodel = json.load(f)
        for service in workmodel:
            app.logger.info(f'service: {service}')
            if service == ID:
                res[service] = workmodel[service]
            else:
                res[service] = {"url": workmodel[service]["url"], "path": workmodel[service]["path"]}
    return res

globalDict['work_model'] = read_config_files()

if "request_method" in globalDict['work_model'][ID].keys():
    request_method = globalDict['work_model'][ID]["request_method"].lower()
else:
    request_method = "rest"

########################### PROMETHEUS METRICS
registry = CollectorRegistry()
multiprocess.MultiProcessCollector(registry)

CONTENT_TYPE_LATEST = str('text/plain; version=0.0.4; charset=utf-8')

# Enhanced metrics for inter-service communication
HTTP_REQUEST_DURATION = Histogram(
    'http_request_duration_seconds', 
    'HTTP request duration in seconds',
    ['service', 'endpoint', 'method', 'status_code'],
    registry=registry,
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
)

HTTP_REQUESTS_TOTAL = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['service', 'endpoint', 'method', 'status_code'],
    registry=registry
)

RESPONSE_SIZE = Summary(
    'mub_response_size', 
    'Response size',
    ['zone', 'app_name', 'method', 'endpoint', 'from', 'kubernetes_service'],
    registry=registry
)

INTERNAL_PROCESSING = Summary(
    'mub_internal_processing_latency_milliseconds',
    'Latency of internal service',
    ['zone', 'app_name', 'method', 'endpoint'],
    registry=registry
)

EXTERNAL_PROCESSING = Summary(
    'mub_external_processing_latency_milliseconds',
    'Latency of external services',
    ['zone', 'app_name', 'method', 'endpoint'],
    registry=registry
)

REQUEST_PROCESSING = Summary(
    'mub_request_processing_latency_milliseconds',
    'Request latency including external and internal service',
    ['zone', 'app_name', 'method', 'endpoint', 'from', 'kubernetes_service'],
    registry=registry
)

buckets = [0.5, 1, 10, 100, 1000, 10000, float("inf")]

INTERNAL_PROCESSING_BUCKET = Histogram(
    'mub_internal_processing_latency_milliseconds_bucket',
    'Latency of internal service',
    ['zone', 'app_name', 'method', 'endpoint'],
    registry=registry,
    buckets=buckets
)

EXTERNAL_PROCESSING_BUCKET = Histogram(
    'mub_external_processing_latency_milliseconds_bucket',
    'Latency of external services',
    ['zone', 'app_name', 'method', 'endpoint'],
    registry=registry,
    buckets=buckets
)

REQUEST_PROCESSING_BUCKET = Histogram(
    'mub_request_processing_latency_milliseconds_bucket',
    'Request latency including external and internal service',
    ['zone', 'app_name', 'method', 'endpoint', 'from', 'kubernetes_service'],
    registry=registry,
    buckets=buckets
)


# ================================================================
# NEW ENDPOINTS FOR INTER-SERVICE COMMUNICATION
# ================================================================

@app.route('/process', methods=['GET', 'POST'])
def service0_process():
    """Service0 endpoint - calls service1"""
    start_time = time.time()
    
    try:
        app.logger.info(f'{ID}: /process endpoint called')
        
        # Execute internal processing
        internal_start = time.time()
        body = run_internal_service(globalDict['work_model'][ID].get('internal_service', {}))
        internal_duration = time.time() - internal_start
        
        # Call service1 if this is service0
        if ID == 's0':
            import requests
            protocol = COMM_PROTOCOL
            service1_url = f"{protocol}://s1.{os.environ.get('NAMESPACE', 'default')}.svc.cluster.local:80/validate"
            
            app.logger.info(f"Calling service1 at {service1_url}")
            verify_ssl = False if protocol == "https" else True
            
            try:
                resp = requests.get(service1_url, timeout=10, verify=verify_ssl)
                resp.raise_for_status()
                app.logger.info(f"Service1 response: {resp.status_code}")
            except Exception as e:
                app.logger.error(f"Error calling service1: {e}")
        
        duration = time.time() - start_time
        HTTP_REQUEST_DURATION.labels(
            service=ID,
            endpoint='/process',
            method=request.method,
            status_code=200
        ).observe(duration)
        
        HTTP_REQUESTS_TOTAL.labels(
            service=ID,
            endpoint='/process',
            method=request.method,
            status_code=200
        ).inc()
        
        return make_response({"status": "ok", "service": ID, "body_length": len(body)}, 200)
    
    except Exception as e:
        duration = time.time() - start_time
        HTTP_REQUEST_DURATION.labels(
            service=ID,
            endpoint='/process',
            method=request.method,
            status_code=500
        ).observe(duration)
        
        HTTP_REQUESTS_TOTAL.labels(
            service=ID,
            endpoint='/process',
            method=request.method,
            status_code=500
        ).inc()
        
        app.logger.error(f"Error in /process: {e}")
        return make_response({"error": str(e)}, 500)


@app.route('/validate', methods=['GET', 'POST'])
def service1_validate():
    """Service1 endpoint - calls service-db"""
    start_time = time.time()
    
    try:
        app.logger.info(f'{ID}: /validate endpoint called')
        
        # Execute internal processing
        internal_start = time.time()
        body = run_internal_service(globalDict['work_model'][ID].get('internal_service', {}))
        internal_duration = time.time() - internal_start
        
        # Call service-db if this is service1
        if ID == 's1':
            import requests
            protocol = COMM_PROTOCOL
            db_url = f"{protocol}://sdb1.{os.environ.get('NAMESPACE', 'default')}.svc.cluster.local:80/query"
            
            app.logger.info(f"Calling service-db at {db_url}")
            verify_ssl = False if protocol == "https" else True
            
            try:
                resp = requests.get(db_url, timeout=10, verify=verify_ssl)
                resp.raise_for_status()
                app.logger.info(f"Service-db response: {resp.status_code}")
            except Exception as e:
                app.logger.error(f"Error calling service-db: {e}")
        
        duration = time.time() - start_time
        HTTP_REQUEST_DURATION.labels(
            service=ID,
            endpoint='/validate',
            method=request.method,
            status_code=200
        ).observe(duration)
        
        HTTP_REQUESTS_TOTAL.labels(
            service=ID,
            endpoint='/validate',
            method=request.method,
            status_code=200
        ).inc()
        
        return make_response({"status": "ok", "service": ID, "body_length": len(body)}, 200)
    
    except Exception as e:
        duration = time.time() - start_time
        HTTP_REQUEST_DURATION.labels(
            service=ID,
            endpoint='/validate',
            method=request.method,
            status_code=500
        ).observe(duration)
        
        HTTP_REQUESTS_TOTAL.labels(
            service=ID,
            endpoint='/validate',
            method=request.method,
            status_code=500
        ).inc()
        
        app.logger.error(f"Error in /validate: {e}")
        return make_response({"error": str(e)}, 500)


@app.route('/query', methods=['GET', 'POST'])
def servicedb_query():
    """Service-DB endpoint - final endpoint in chain"""
    start_time = time.time()
    
    try:
        app.logger.info(f'{ID}: /query endpoint called')
        
        # Execute internal processing (simulate DB query)
        internal_start = time.time()
        body = run_internal_service(globalDict['work_model'][ID].get('internal_service', {}))
        internal_duration = time.time() - internal_start
        
        duration = time.time() - start_time
        HTTP_REQUEST_DURATION.labels(
            service=ID,
            endpoint='/query',
            method=request.method,
            status_code=200
        ).observe(duration)
        
        HTTP_REQUESTS_TOTAL.labels(
            service=ID,
            endpoint='/query',
            method=request.method,
            status_code=200
        ).inc()
        
        return make_response({"status": "ok", "service": ID, "body_length": len(body), "data": "query_result"}, 200)
    
    except Exception as e:
        duration = time.time() - start_time
        HTTP_REQUEST_DURATION.labels(
            service=ID,
            endpoint='/query',
            method=request.method,
            status_code=500
        ).observe(duration)
        
        HTTP_REQUESTS_TOTAL.labels(
            service=ID,
            endpoint='/query',
            method=request.method,
            status_code=500
        ).inc()
        
        app.logger.error(f"Error in /query: {e}")
        return make_response({"error": str(e)}, 500)


# ================================================================
# ORIGINAL ENDPOINTS (preserved)
# ================================================================

@app.route(f"{globalDict['work_model'][ID]['path']}", methods=['GET', 'POST'])
def start_worker():
    global globalDict
    
    try:
        start_request_processing = time.time()
        app.logger.info('Request Received')
        
        query_string = request.query_string.decode()
        behaviour_id = request.args.get('bid', default='default', type=str)
        
        my_work_model = globalDict['work_model'][ID]
        my_service_graph = my_work_model['external_services']
        my_internal_service = my_work_model['internal_service']

        if behaviour_id != 'default' and "alternative_behaviors" in my_work_model.keys():
            if behaviour_id in my_work_model['alternative_behaviors'].keys():
                if "internal_services" in my_work_model['alternative_behaviors'][behaviour_id].keys():
                    my_internal_service = my_work_model['alternative_behaviors'][behaviour_id]['internal_service']

        jaeger_headers = dict()
        for jhdr in jaeger_headers_list:
            val = request.headers.get(jhdr)
            if val is not None:
                jaeger_headers[jhdr] = val

        trace = dict()
        if request.method == 'POST':
            trace = request.json
            assert len(trace.keys()) == 1, 'bad trace format'
            assert ID == list(trace)[0].split(traceEscapeString)[0], "bad trace format, ID"
            trace[ID] = trace[list(trace)[0]]
            
        if len(trace) > 0:
            n_groups = len(trace[ID])
            my_service_graph = list()
            for i in range(0, n_groups):
                group = trace[ID][i]
                group_dict = dict()
                group_dict['seq_len'] = len(group)
                group_dict['services'] = list(group.keys())
                my_service_graph.append(group_dict)
        else:
            if behaviour_id != 'default' and "alternative_behaviors" in my_work_model.keys():
                if behaviour_id in my_work_model['alternative_behaviors'].keys():
                    if "external_services" in my_work_model['alternative_behaviors'][behaviour_id].keys():
                        my_service_graph = my_work_model['alternative_behaviors'][behaviour_id]['external_services']

        app.logger.info("*************** INTERNAL SERVICE STARTED ***************")
        start_local_processing = time.time()
        body = run_internal_service(my_internal_service)
        local_processing_latency = time.time() - start_local_processing
        INTERNAL_PROCESSING.labels(ZONE, K8S_APP, request.method, request.path).observe(local_processing_latency * 1000)
        INTERNAL_PROCESSING_BUCKET.labels(ZONE, K8S_APP, request.method, request.path).observe(local_processing_latency * 1000)
        RESPONSE_SIZE.labels(ZONE, K8S_APP, request.method, request.path, request.remote_addr, ID).observe(len(body))
        app.logger.info("len(body): %d" % len(body))
        app.logger.info("############### INTERNAL SERVICE FINISHED! ###############")

        start_external_request_processing = time.time()
        app.logger.info("*************** EXTERNAL SERVICES STARTED ***************")
        
        if len(my_service_graph) > 0:
            if len(trace) > 0:
                service_error_dict = run_external_service(my_service_graph, globalDict['work_model'], query_string, trace[ID], app, jaeger_headers)
            else:
                service_error_dict = run_external_service(my_service_graph, globalDict['work_model'], query_string, dict(), app, jaeger_headers)
            if len(service_error_dict):
                app.logger.error(service_error_dict)
                app.logger.error("Error in request external services")
                return make_response(json.dumps({"message": "Error in external services request"}), 500)
        app.logger.info("############### EXTERNAL SERVICES FINISHED! ###############")

        response = make_response(body)
        response.mimetype = "text/plain"
        EXTERNAL_PROCESSING.labels(ZONE, K8S_APP, request.method, request.path).observe((time.time() - start_external_request_processing) * 1000)
        EXTERNAL_PROCESSING_BUCKET.labels(ZONE, K8S_APP, request.method, request.path).observe((time.time() - start_external_request_processing) * 1000)
        
        REQUEST_PROCESSING.labels(ZONE, K8S_APP, request.method, request.path, request.remote_addr, ID).observe((time.time() - start_request_processing) * 1000)
        REQUEST_PROCESSING_BUCKET.labels(ZONE, K8S_APP, request.method, request.path, request.remote_addr, ID).observe((time.time() - start_request_processing) * 1000)

        # Track with new metrics
        duration = time.time() - start_request_processing
        HTTP_REQUEST_DURATION.labels(
            service=ID,
            endpoint=request.path,
            method=request.method,
            status_code=200
        ).observe(duration)
        
        HTTP_REQUESTS_TOTAL.labels(
            service=ID,
            endpoint=request.path,
            method=request.method,
            status_code=200
        ).inc()

        response.headers.update(jaeger_headers)
        return response
        
    except Exception as err:
        app.logger.error("Error in start_worker", err)
        return json.dumps({"message": "Error"}), 500


@app.route('/metrics')
def metrics():
    return Response(prometheus_client.generate_latest(registry), mimetype=CONTENT_TYPE_LATEST)


@app.route('/health')
def health():
    return {"status": "healthy", "service": ID}, 200


@app.route('/ready')
def ready():
    return {"status": "ready", "service": ID}, 200


class HttpServer(gunicorn.app.base.BaseApplication):
    def __init__(self, app, options=None):
        self.options = options or {}
        self.application = app
        super().__init__()

    def load_config(self):
        config = {key: value for key, value in self.options.items()
                  if key in self.cfg.settings and value is not None}
        for key, value in config.items():
            self.cfg.set(key.lower(), value)

    def load(self):
        return self.application


gRPC_port = 51313

class gRPCThread(Thread, pb2_grpc.MicroServiceServicer):
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=int(TN)))

    def __init__(self):
        Thread.__init__(self)

    def GetMicroServiceResponse(self, req, context):
        try:
            start_request_processing = time.time()
            app.logger.info('Request Received')
            message = req.message
            remote_address = context.peer().split(":")[1]
            app.logger.info(f'I am service: {ID} and I received this message: --> "{message}"')

            app.logger.info("*************** INTERNAL SERVICE STARTED ***************")
            start_local_processing = time.time()
            body = run_internal_service(my_work_model["internal_service"])
            local_processing_latency = time.time() - start_local_processing
            INTERNAL_PROCESSING.labels(ZONE, K8S_APP, "grpc", "grpc").observe(local_processing_latency * 1000)
            RESPONSE_SIZE.labels(ZONE, K8S_APP, "grpc", "grpc", remote_address, ID).observe(len(body))
            app.logger.info("len(body): %d" % len(body))
            app.logger.info("############### INTERNAL SERVICE FINISHED! ###############")

            app.logger.info("*************** EXTERNAL SERVICES STARTED ***************")
            start_external_request_processing = time.time()
            if len(my_service_graph) > 0:
                service_error_dict = run_external_service(my_service_graph, globalDict['work_model'])
                if len(service_error_dict):
                    app.logger.error(service_error_dict)
                    result = {'text': f"Error in external services request", 'status_code': False}
                    return pb2.MessageResponse(**result)
            app.logger.info("############### EXTERNAL SERVICES FINISHED! ###############")

            result = {'text': body, 'status_code': True}
            EXTERNAL_PROCESSING.labels(ZONE, K8S_APP, "grpc", "grpc").observe((time.time() - start_external_request_processing) * 1000)
            REQUEST_PROCESSING.labels(ZONE, K8S_APP, "grpc", "grpc", remote_address, ID).observe(
                (time.time() - start_request_processing) * 1000)
            return pb2.MessageResponse(**result)
        except Exception as err:
            app.logger.error("Error: in GetMicroServiceResponse,", err)
            result = {'text': f"Error: in GetMicroServiceResponse, {str(err)}", 'status_code': False}
            return pb2.MessageResponse(**result)

    def run(self):
        pb2_grpc.add_MicroServiceServicer_to_server(self, self.server)
        self.server.add_insecure_port(f'[::]:{gRPC_port}')
        self.server.start()


if __name__ == '__main__':
    if request_method == "rest":
        init_REST(app)
        
        bind_port = 8080
        # If HTTPS is enabled, configure SSL context
        if COMM_PROTOCOL == "https":
            app.logger.info("HTTPS mode enabled - using self-signed certificates")
            # SSL configuration would be handled by reverse proxy or ingress
            # For now, app still binds to 8080, SSL termination happens at ingress level
        
        options_gunicorn = {
            'bind': '%s:%s' % ('0.0.0.0', bind_port),
            'workers': PN,
            'config': "/app/gunicorn.conf.py",
            'threads': TN
        }
        HttpServer(app, options_gunicorn).run()
        
    elif request_method == "grpc":
        my_work_model = globalDict['work_model'][ID]
        my_service_graph = my_work_model['external_services']
        init_gRPC(my_service_graph, globalDict['work_model'], gRPC_port, app)
        grpc_thread = gRPCThread()
        grpc_thread.run()
        app.run(host='0.0.0.0', port=8080, threaded=True)
    else:
        app.logger.info("Error: Unsupported request method")
        sys.exit(0)
