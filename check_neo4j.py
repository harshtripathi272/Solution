import os
from dotenv import load_dotenv

load_dotenv()

try:
    from neo4j import GraphDatabase
    uri = os.getenv("NEO4J_URI", "").strip()
    user = os.getenv("NEO4J_USER", "").strip()
    password = os.getenv("NEO4J_PASSWORD", "").strip()

    if uri and user and password:
        driver = GraphDatabase.driver(uri, auth=(user, password))
        with driver.session() as session:
            result = session.run("MATCH (n) RETURN count(n) as node_count")
            count = result.single()["node_count"]
            print(f"Neo4j has {count} nodes")
            
            # Check for Community nodes
            result = session.run("MATCH (c:Community) RETURN count(c) as community_count")
            comm_count = result.single()["community_count"]
            print(f"Neo4j has {comm_count} Community nodes")
        driver.close()
    else:
        print("Neo4j credentials not set")
except ImportError:
    print("Neo4j driver not installed")
except Exception as e:
    print(f"Error checking Neo4j: {e}")